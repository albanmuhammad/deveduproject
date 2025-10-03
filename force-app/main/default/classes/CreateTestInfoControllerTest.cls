@IsTest
private class CreateTestInfoControllerTest {
    /* ======================== *
     *  Generic Schema Helpers  *
     * ======================== */

    // Returns a value for Intake__c that matches the field type:
    // - If Intake__c is a picklist: returns the first active picklist value (String).
    // - If Intake__c is a lookup: inserts a minimal referenced record and returns its Id.
    // - Else: returns null (not expected, but safe).
    private static Object buildIntakeValueFor(String sobjectApiName) {
        Schema.SObjectType sType = Schema.getGlobalDescribe().get(sobjectApiName);
        if (sType == null) return null;

        Schema.DescribeSObjectResult d = sType.getDescribe();
        Map<String, Schema.SObjectField> fields = d.fields.getMap();
        if (!fields.containsKey('Intake__c')) return null;

        Schema.DescribeFieldResult f = fields.get('Intake__c').getDescribe();
        Schema.DisplayType t = f.getType();

        if (t == Schema.DisplayType.Picklist) {
            // Use first active picklist value
            for (Schema.PicklistEntry pe : f.getPicklistValues()) {
                if (pe.isActive()) return pe.getValue();
            }
            // As fallback, just return the first one if none marked active
            List<Schema.PicklistEntry> all = f.getPicklistValues();
            return all.isEmpty() ? null : all[0].getValue();
        }

        if (t == Schema.DisplayType.Reference) {
            // Create a minimal referenced record using the first ref target
            List<Schema.SObjectType> refs = f.getReferenceTo();
            if (refs == null || refs.isEmpty()) return null;

            Schema.SObjectType refType = refs[0];
            SObject ref = refType.newSObject();
            // Try to set Name if it exists; otherwise just insert blank SObject
            if (ref.getSObjectType().getDescribe().fields.getMap().containsKey('Name')) {
                ref.put('Name', 'UT Intake Ref');
            }
            insert ref;
            return ref.Id;
        }

        return null;
    }

    // Puts Intake__c on the given record if the field exists
    private static void ensureIntakeOn(SObject sobj) {
        Schema.SObjectType t = sobj.getSObjectType();
        Map<String, Schema.SObjectField> fm = t.getDescribe().fields.getMap();
        if (!fm.containsKey('Intake__c')) return;

        Object v = buildIntakeValueFor(String.valueOf(t));
        if (v != null) sobj.put('Intake__c', v);
    }

    // Utility to set the “non-null only” flag Batch_Study_Program__c without schema coupling
    private static void setHasBatchStudyProgram(SObject sobj) {
        Schema.SObjectType t = sobj.getSObjectType();
        if (t.getDescribe().fields.getMap().containsKey('Batch_Study_Program__c')) {
            sobj.put('Batch_Study_Program__c', 'ANY_NON_NULL');
        }
    }

    /* ======================== *
     *  Test Data Builders      *
     * ======================== */

    private static Account makeAccount() {
        Account a = new Account(Name = 'Acme Test');
        insert a;
        return a;
    }

    private static Opportunity makeOpportunity(Id accountId, String name) {
        Opportunity o = new Opportunity(
            Name      = name,
            AccountId = accountId,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert o;
        return o;
    }

    private static Master_Batches__c makeBatch(Datetime sched) {
        Master_Batches__c b = new Master_Batches__c(
            Name = 'Batch-UT',
            Test_Schedule__c = sched
        );
        // Ensure required Intake__c regardless of type
        ensureIntakeOn(b);
        insert b;
        return b;
    }

    /* ======================== *
     *  Tests                   *
     * ======================== */

    // === Test 1: Creates Test_Information__c with batch schedule copied ===
    @IsTest
    static void testCreatesWithBatchAndSchedule() {
        Account a = makeAccount();
        Opportunity opp = makeOpportunity(a.Id, 'Opp A');

        // Make batch with known schedule + required Intake__c
        Datetime sched = System.now().addDays(7);
        Master_Batches__c batch = makeBatch(sched);

        // Query old version with Master_Batch__c INCLUDED
        Opportunity oldVersion = [
            SELECT Id, Name, AccountId, Master_Batch__c
            FROM Opportunity
            WHERE Id = :opp.Id
        ];

        // new version: change name, set batch, set “has batch study program”
        Opportunity newVersion = oldVersion.clone(true, true, false, false);
        newVersion.Name = 'Opp B';
        newVersion.Master_Batch__c = batch.Id;
        setHasBatchStudyProgram(newVersion);

        List<Opportunity> newList = new List<Opportunity>{ newVersion };
        Map<Id, Opportunity> oldMap = new Map<Id, Opportunity>{ oldVersion.Id => oldVersion };

        Test.startTest();
        CreateTestInfoController.handleTestInfoCreation(newList, oldMap);
        Test.stopTest();

        // Assert one TI created and schedule copied
        Test_Information__c ti = [
            SELECT Id, Application_Progress__c, Applicant__c, Master_Batch__c, Name, Test_Schedule__c
            FROM Test_Information__c
            WHERE Application_Progress__c = :opp.Id
            LIMIT 1
        ];
        System.assertEquals(opp.Id, ti.Application_Progress__c);
        System.assertEquals(a.Id, ti.Applicant__c);
        System.assertEquals(batch.Id, ti.Master_Batch__c);
        System.assertEquals('Test/' + newVersion.Name, ti.Name);
        System.assertEquals(sched, ti.Test_Schedule__c);
    }

    // === Test 2: Duplicate prevention ===
    @IsTest
    static void testPreventsDuplicates() {
        Account a = makeAccount();
        Opportunity opp = makeOpportunity(a.Id, 'Opp X');

        // Seed existing TI; set Intake__c on TI if present/required
        Test_Information__c existing = new Test_Information__c(
            Name = 'Existing',
            Application_Progress__c = opp.Id,
            Applicant__c = a.Id
        );
        ensureIntakeOn(existing);
        insert existing;

        // old/new with Master_Batch__c included in SOQL
        Opportunity oldVersion = [
            SELECT Id, Name, AccountId, Master_Batch__c
            FROM Opportunity
            WHERE Id = :opp.Id
        ];
        Opportunity newVersion = oldVersion.clone(true, true, false, false);
        newVersion.Name = 'Opp X Renamed';
        setHasBatchStudyProgram(newVersion); // non-null flag; no batch needed to hit duplicate guard

        Test.startTest();
        CreateTestInfoController.handleTestInfoCreation(
            new List<Opportunity>{ newVersion },
            new Map<Id, Opportunity>{ oldVersion.Id => oldVersion }
        );
        Test.stopTest();

        Integer countTi = [
            SELECT COUNT()
            FROM Test_Information__c
            WHERE Application_Progress__c = :opp.Id
        ];
        System.assertEquals(1, countTi, 'Should not create a duplicate Test_Information__c');
    }

    // === Test 3: Creates when Master_Batch__c is null (schedule left null) ===
    @IsTest
    static void testCreatesWithoutBatch_ScheduleNull() {
        Account a = makeAccount();
        Opportunity opp = makeOpportunity(a.Id, 'Opp C');

        Opportunity oldVersion = [
            SELECT Id, Name, AccountId, Master_Batch__c
            FROM Opportunity
            WHERE Id = :opp.Id
        ];
        Opportunity newVersion = oldVersion.clone(true, true, false, false);
        newVersion.Name = 'Opp C+';
        setHasBatchStudyProgram(newVersion); // non-null
        // Master_Batch__c intentionally left null

        Test.startTest();
        CreateTestInfoController.handleTestInfoCreation(
            new List<Opportunity>{ newVersion },
            new Map<Id, Opportunity>{ oldVersion.Id => oldVersion }
        );
        Test.stopTest();

        Test_Information__c ti = [
            SELECT Id, Test_Schedule__c, Master_Batch__c
            FROM Test_Information__c
            WHERE Application_Progress__c = :opp.Id
            LIMIT 1
        ];
        System.assertEquals(null, ti.Master_Batch__c, 'Master_Batch__c should be null');
        System.assertEquals(null, ti.Test_Schedule__c, 'Schedule should be null when there is no Master_Batch__c');
    }

    // === Test 4: Guard rails (no create when name not changed / missing prereqs) ===
    @IsTest
    static void testNoCreateWhenPrereqsMissing() {
        Account a = makeAccount();
        Opportunity opp = makeOpportunity(a.Id, 'Opp Guard');

        // Case A: name not changed
        Opportunity oldA = [
            SELECT Id, Name, AccountId, Master_Batch__c
            FROM Opportunity
            WHERE Id = :opp.Id
        ];
        Opportunity newA = oldA.clone(true, true, false, false);
        // same name
        setHasBatchStudyProgram(newA); // even if set, should not fire because name unchanged

        // Case B: missing AccountId
        Opportunity oldB = [
            SELECT Id, Name, AccountId, Master_Batch__c
            FROM Opportunity
            WHERE Id = :opp.Id
        ];
        Opportunity newB = oldB.clone(true, true, false, false);
        newB.Name = 'Opp Guard New';
        newB.AccountId = null; // missing account
        setHasBatchStudyProgram(newB);

        Test.startTest();
        CreateTestInfoController.handleTestInfoCreation(
            new List<Opportunity>{ newA, newB },
            new Map<Id, Opportunity>{ oldA.Id => oldA, oldB.Id => oldB }
        );
        Test.stopTest();

        Integer countTi = [
            SELECT COUNT()
            FROM Test_Information__c
            WHERE Application_Progress__c = :opp.Id
        ];
        System.assertEquals(0, countTi, 'Nothing should be created when name unchanged or AccountId missing');
    }
}