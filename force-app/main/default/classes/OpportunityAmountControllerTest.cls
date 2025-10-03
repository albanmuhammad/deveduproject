@IsTest
private class OpportunityAmountControllerTest {

    /* =========================
       Generic helpers
       ========================= */

    // If the SObject has an Intake__c field and it’s required in your org,
    // this sets a valid value:
    // - Picklist => first active value
    // - Lookup   => inserts a minimal referenced record and uses its Id
    private static void ensureIntakeOn(SObject sobj) {
        Schema.SObjectType t = sobj.getSObjectType();
        Map<String, Schema.SObjectField> fields = t.getDescribe().fields.getMap();
        if (!fields.containsKey('Intake__c')) return;

        Schema.DescribeFieldResult f = fields.get('Intake__c').getDescribe();
        Schema.DisplayType typ = f.getType();

        if (typ == Schema.DisplayType.Picklist) {
            String val;
            for (Schema.PicklistEntry pe : f.getPicklistValues()) {
                if (pe.isActive()) { val = pe.getValue(); break; }
            }
            if (val == null && !f.getPicklistValues().isEmpty()) {
                val = f.getPicklistValues()[0].getValue();
            }
            if (val != null) sobj.put('Intake__c', val);
        } else if (typ == Schema.DisplayType.Reference) {
            List<Schema.SObjectType> refs = f.getReferenceTo();
            if (refs != null && !refs.isEmpty()) {
                SObject ref = refs[0].newSObject();
                if (refs[0].getDescribe().fields.getMap().containsKey('Name')) {
                    ref.put('Name', 'UT Intake Ref');
                }
                insert ref;
                sobj.put('Intake__c', ref.Id);
            }
        }
    }

    // Safely set Name only if it’s a writeable Text Name (not Auto Number)
    private static void setNameIfWritable(SObject sobj, String value) {
        Map<String, Schema.SObjectField> m = sobj.getSObjectType().getDescribe().fields.getMap();
        if (!m.containsKey('Name')) return;
        Schema.DescribeFieldResult df = m.get('Name').getDescribe();
        if (df.getType() == Schema.DisplayType.String && df.isCreateable()) {
            sobj.put('Name', value);
        }
    }

    private static Account makeAccount() {
        Account a = new Account(Name = 'Acme Co');
        insert a;
        return a;
    }

    private static Opportunity makeOpp(Id accountId, String name) {
        Opportunity o = new Opportunity(
            Name = name,
            AccountId = accountId,
            StageName = 'Registration',
            CloseDate = Date.today().addDays(10)
        );
        insert o;
        return o;
    }

    private static Study_Program_Intake__c makeStudyProgramIntake(Decimal fee) {
        Study_Program_Intake__c i = new Study_Program_Intake__c();
        setNameIfWritable(i, 'AY 2025/2026');
        i.put('Application_Fee__c', fee);
        ensureIntakeOn(i);
        insert i;
        return i;
    }

    private static Batch_Study_Program__c makeBsp(Id intakeId) {
        Batch_Study_Program__c bsp = new Batch_Study_Program__c();
        setNameIfWritable(bsp, 'BSP A');
        bsp.put('Study_Program_Intake__c', intakeId);
        ensureIntakeOn(bsp);
        insert bsp;
        return bsp;
    }

    private static Master_Batches__c makeBatch(Decimal discountPercent) {
        Master_Batches__c mb = new Master_Batches__c();
        setNameIfWritable(mb, 'Batch Alpha');
        mb.put('Discount_Percentage__c', discountPercent);
        ensureIntakeOn(mb);
        insert mb;
        return mb;
    }

    // ⬇️ FIX: mark Is_Attend__c = true whenever a score is provided
    private static Test_Information__c makeTestInfo(Id oppId, Id accountId, Decimal score) {
        Test_Information__c ti = new Test_Information__c();
        setNameIfWritable(ti, 'TI ' + oppId);
        ti.put('Application_Progress__c', oppId);
        ti.put('Applicant__c', accountId);
        if (score != null) {
            // satisfy your validation rule
            if (ti.getSObjectType().getDescribe().fields.getMap().containsKey('Is_Attend__c')) {
                ti.put('Is_Attend__c', true);
            }
            ti.put('Test_Score__c', score);
        }
        ensureIntakeOn(ti);
        insert ti;
        return ti;
    }

    private static void seedTestDiscounts() {
        Test_Discount__c d1 = new Test_Discount__c();
        setNameIfWritable(d1, 'Bronze');
        d1.put('Minimum_Test_Score__c', 70);
        d1.put('Discount_Percentage__c', 5);

        Test_Discount__c d2 = new Test_Discount__c();
        setNameIfWritable(d2, 'Gold');
        d2.put('Minimum_Test_Score__c', 85);
        d2.put('Discount_Percentage__c', 15);

        insert new List<Test_Discount__c>{ d1, d2 };
    }

    /* =========================
       Tests
       ========================= */

    @IsTest
    static void testAmount_BatchAndTestDiscounts() {
        Account a = makeAccount();
        Study_Program_Intake__c intake = makeStudyProgramIntake(20000000);
        Batch_Study_Program__c bsp = makeBsp(intake.Id);
        Master_Batches__c batch = makeBatch(10);
        seedTestDiscounts();

        Opportunity o = makeOpp(a.Id, 'Opp BT');
        makeTestInfo(o.Id, a.Id, 88);

        Opportunity newO = new Opportunity(
            Id = o.Id,
            StageName = 'Test Passed',
            Batch_Study_Program__c = bsp.Id,
            Master_Batch__c = batch.Id
        );
        Opportunity oldO = new Opportunity(Id = o.Id, StageName = 'Registration');

        Test.startTest();
        OpportunityAmountController.handleAmountCalculation(
            new List<Opportunity>{ newO },
            new Map<Id, Opportunity>{ oldO.Id => oldO }
        );
        Test.stopTest();

        Opportunity after = [SELECT Amount FROM Opportunity WHERE Id = :o.Id];
        System.assertEquals(15300000, after.Amount);
    }

    @IsTest
    static void testAmount_BatchOnly_NoTestScore() {
        Account a = makeAccount();
        Study_Program_Intake__c intake = makeStudyProgramIntake(20000000);
        Batch_Study_Program__c bsp = makeBsp(intake.Id);
        Master_Batches__c batch = makeBatch(10);
        seedTestDiscounts();

        Opportunity o = makeOpp(a.Id, 'Opp B');
        makeTestInfo(o.Id, a.Id, null); // no test score

        Opportunity newO = new Opportunity(
            Id = o.Id,
            StageName = 'Test Passed',
            Batch_Study_Program__c = bsp.Id,
            Master_Batch__c = batch.Id
        );
        Opportunity oldO = new Opportunity(Id = o.Id, StageName = 'Registration');

        Test.startTest();
        OpportunityAmountController.handleAmountCalculation(
            new List<Opportunity>{ newO },
            new Map<Id, Opportunity>{ oldO.Id => oldO }
        );
        Test.stopTest();

        Opportunity after = [SELECT Amount FROM Opportunity WHERE Id = :o.Id];
        System.assertEquals(18000000, after.Amount);
    }

    @IsTest
    static void testAmount_TestOnly_NoBatch() {
        Account a = makeAccount();
        Study_Program_Intake__c intake = makeStudyProgramIntake(20000000);
        Batch_Study_Program__c bsp = makeBsp(intake.Id);
        seedTestDiscounts();

        Opportunity o = makeOpp(a.Id, 'Opp T');
        makeTestInfo(o.Id, a.Id, 90); // qualifies for 15%

        Opportunity newO = new Opportunity(
            Id = o.Id,
            StageName = 'Test Passed',
            Batch_Study_Program__c = bsp.Id
        );
        Opportunity oldO = new Opportunity(Id = o.Id, StageName = 'Registration');

        Test.startTest();
        OpportunityAmountController.handleAmountCalculation(
            new List<Opportunity>{ newO },
            new Map<Id, Opportunity>{ oldO.Id => oldO }
        );
        Test.stopTest();

        Opportunity after = [SELECT Amount FROM Opportunity WHERE Id = :o.Id];
        System.assertEquals(17000000, after.Amount);
    }

    @IsTest
    static void testNoUpdate_WhenStageDidNotChangeToTestPassed() {
        Account a = makeAccount();
        Study_Program_Intake__c intake = makeStudyProgramIntake(10000000);
        Batch_Study_Program__c bsp = makeBsp(intake.Id);
        Master_Batches__c batch = makeBatch(50);
        Opportunity o = makeOpp(a.Id, 'Opp SKIP');
        makeTestInfo(o.Id, a.Id, 100);

        Opportunity newO = new Opportunity(
            Id = o.Id,
            StageName = 'Test Passed',
            Batch_Study_Program__c = bsp.Id,
            Master_Batch__c = batch.Id
        );
        Opportunity oldO = new Opportunity(Id = o.Id, StageName = 'Test Passed');

        Test.startTest();
        OpportunityAmountController.handleAmountCalculation(
            new List<Opportunity>{ newO },
            new Map<Id, Opportunity>{ oldO.Id => oldO }
        );
        Test.stopTest();

        Opportunity after = [SELECT Amount FROM Opportunity WHERE Id = :o.Id];
        System.assertEquals(null, after.Amount);
    }
}