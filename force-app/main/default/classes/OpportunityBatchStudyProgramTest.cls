@IsTest
private class OpportunityBatchStudyProgramTest {

    // ---------- helpers ----------
    private static void setIfExists(SObject rec, String api, Object val) {
        Map<String, Schema.SObjectField> f = rec.getSObjectType().getDescribe().fields.getMap();
        if (f.containsKey(api)) rec.put(api, val);
    }
    private static String firstPickVal(Schema.DescribeFieldResult dfr) {
        List<Schema.PicklistEntry> vals = dfr.getPicklistValues();
        return vals.isEmpty() ? null : vals[0].getValue();
    }
    private static String pickValOr(List<String> preferred, Schema.DescribeFieldResult dfr) {
        Set<String> wanted = new Set<String>();
        for (String p : preferred) wanted.add(p.toLowerCase());
        for (Schema.PicklistEntry e : dfr.getPicklistValues()) {
            if (wanted.contains(e.getValue().toLowerCase())) return e.getValue();
        }
        return firstPickVal(dfr);
    }

    @TestSetup
    static void setupData() {
        // === Study Program ===
        SObject sp = (SObject)Schema.getGlobalDescribe().get('Study_Program__c').newSObject();

        // Common filters on the SP lookup: often require an "active/open" flag
        Map<String, Schema.SObjectField> spFields = sp.getSObjectType().getDescribe().fields.getMap();
        if (spFields.containsKey('Is_Active__c')) sp.put('Is_Active__c', true);
        if (spFields.containsKey('Active__c'))    sp.put('Active__c', true);
        if (spFields.containsKey('Open_for_Registration__c')) sp.put('Open_for_Registration__c', true);
        if (spFields.containsKey('Status__c')) {
            Schema.DescribeFieldResult dfr = spFields.get('Status__c').getDescribe();
            sp.put('Status__c', pickValOr(new List<String>{'Active','Open','Aktif','Buka'}, dfr));
        }

        // ✅ Only set RecordTypeId if the field exists on this object
        if (spFields.containsKey('RecordTypeId')) {
            Schema.DescribeSObjectResult spDescribe = sp.getSObjectType().getDescribe();
            for (Schema.RecordTypeInfo rti : spDescribe.getRecordTypeInfos()) {
                if (rti.isAvailable()) { 
                    sp.put('RecordTypeId', rti.getRecordTypeId()); 
                    break; 
                }
            }
        }
        insert sp;

        // === Master Intake (parent) ===
        SObject intake = (SObject)Schema.getGlobalDescribe().get('Master_Intake__c').newSObject();
        insert intake;

        // === Study Program Intake (must tie to SP and Intake) ===
        SObject spi = (SObject)Schema.getGlobalDescribe().get('Study_Program_Intake__c').newSObject();
        Map<String, Schema.SObjectField> spiFields = spi.getSObjectType().getDescribe().fields.getMap();
        setIfExists(spi, 'Study_Program__c', sp.get('Id'));
        if (spiFields.containsKey('Intake__c')) {
            spi.put('Intake__c', intake.get('Id'));
        } else if (spiFields.containsKey('Master_Intake__c')) {
            spi.put('Master_Intake__c', intake.get('Id'));
        }
        insert spi;

        // === Master Batch (ensure it points to the SAME intake) ===
        SObject batch = (SObject)Schema.getGlobalDescribe().get('Master_Batches__c').newSObject();
        Map<String, Schema.SObjectField> batchFields = batch.getSObjectType().getDescribe().fields.getMap();
        setIfExists(batch, 'Intake__c', intake.get('Id'));
        if (batchFields.containsKey('Test_Schedule__c')) {
            Schema.DisplayType t = batchFields.get('Test_Schedule__c').getDescribe().getType();
            if (t == Schema.DisplayType.DateTime) batch.put('Test_Schedule__c', System.now().addDays(7));
            else                                   batch.put('Test_Schedule__c', Date.today().addDays(7));
        }
        insert batch;

        // === BSP junction (Study Program + SPI + Batch) ===
        SObject bsp = (SObject)Schema.getGlobalDescribe().get('Batch_Study_Program__c').newSObject();
        bsp.put('Study_Program__c', sp.get('Id'));
        bsp.put('Study_Program_Intake__c', spi.get('Id'));
        bsp.put('Master_Batch__c', batch.get('Id'));
        Map<String, Schema.SObjectField> bspFields = bsp.getSObjectType().getDescribe().fields.getMap();
        if (bspFields.containsKey('Intake__c')) bsp.put('Intake__c', intake.get('Id'));
        insert bsp;

        // === Account ===
        Account acc = new Account(Name = 'Acme Education');
        insert acc;

        // === Opportunity that SHOULD update ===
        Opportunity opp1 = new Opportunity(
            Name = 'Temp Name',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            AccountId = acc.Id,
            Study_Program__c = (Id)sp.get('Id'),
            Master_Intake__c = (Id)intake.get('Id'),
            Master_Batch__c = (Id)batch.get('Id')
        );
        insert opp1;

        // === Opportunity that should NOT match (different intake) ===
        SObject intakeOther = (SObject)Schema.getGlobalDescribe().get('Master_Intake__c').newSObject();
        insert intakeOther;

        Opportunity opp2 = new Opportunity(
            Name = 'Another Temp',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(40),
            AccountId = acc.Id,
            Study_Program__c = (Id)sp.get('Id'),
            Master_Intake__c = (Id)intakeOther.get('Id'),
            Master_Batch__c = (Id)batch.get('Id')
        );
        insert opp2;
    }

    @IsTest
    static void testUpdatesWhenKeyFieldsSetOrChanged() {
        Opportunity opp = [
            SELECT Id, Name, Study_Program__c, Master_Intake__c, Master_Batch__c,
                   Batch_Study_Program__c, Test_Schedule__c, AccountId
            FROM Opportunity
            WHERE Name = 'Temp Name' LIMIT 1
        ];

        Test.startTest();
        OpportunityBatchStudyProgramController.handleBatchStudyProgram(
            new List<Opportunity>{ opp }, null
        );
        Test.stopTest();

        Opportunity after = [
            SELECT Id, Name, Batch_Study_Program__c, Test_Schedule__c,
                   Study_Program__c, Master_Intake__c, Master_Batch__c
            FROM Opportunity WHERE Id = :opp.Id
        ];

        // Expected BSP by key fields (not by name)
        Batch_Study_Program__c expectedBsp = [
            SELECT Id, Name
            FROM Batch_Study_Program__c
            WHERE Study_Program__c = :after.Study_Program__c
              AND Study_Program_Intake__r.Master_Intake__c = :after.Master_Intake__c
              AND Master_Batch__c = :after.Master_Batch__c
            LIMIT 1
        ];
        System.assertEquals(expectedBsp.Id, after.Batch_Study_Program__c,
            'Opportunity should link the matching BSP.');

        // Schedule compare (Date vs DateTime)
        Schema.DisplayType oppSchedType = Opportunity.Test_Schedule__c.getDescribe().getType();
        if (oppSchedType == Schema.DisplayType.DateTime) {
            Datetime batchSched = [
                SELECT Test_Schedule__c FROM Master_Batches__c
                WHERE Id = :after.Master_Batch__c LIMIT 1
            ].Test_Schedule__c;
            System.assertEquals(batchSched, (Datetime)after.Test_Schedule__c);
        } else if (oppSchedType == Schema.DisplayType.Date) {
            Date batchSched = [
                SELECT Test_Schedule__c FROM Master_Batches__c
                WHERE Id = :after.Master_Batch__c LIMIT 1
            ].Test_Schedule__c.date();
            System.assertEquals(batchSched, (Date)after.Test_Schedule__c);
        }

        System.assert(after.Name.contains('/REG/'),
            'Opportunity.Name should include "/REG/".');
        System.assert(after.Name.endsWith(expectedBsp.Name),
            'Opportunity.Name should end with the BSP Name.');
    }

    @IsTest
    static void testNoUpdateWhenNoMatchingJunction() {
        Opportunity oppNoMatch = [
            SELECT Id, Name, Batch_Study_Program__c, Test_Schedule__c,
                   Study_Program__c, Master_Intake__c, Master_Batch__c
            FROM Opportunity
            WHERE Name = 'Another Temp' LIMIT 1
        ];
        Id beforeBsp = oppNoMatch.Batch_Study_Program__c;
        Object beforeSchedule = oppNoMatch.Test_Schedule__c;

        Test.startTest();
        OpportunityBatchStudyProgramController.handleBatchStudyProgram(
            new List<Opportunity>{ oppNoMatch }, null
        );
        Test.stopTest();

        Opportunity after = [
            SELECT Id, Batch_Study_Program__c, Test_Schedule__c
            FROM Opportunity WHERE Id = :oppNoMatch.Id
        ];
        System.assertEquals(beforeBsp, after.Batch_Study_Program__c);
        System.assertEquals(beforeSchedule, after.Test_Schedule__c);
    }

    @IsTest
    static void testNoOpWhenFieldsDidNotChangeOnUpdate() {
        Opportunity opp = [
            SELECT Id, Name, Study_Program__c, Master_Intake__c, Master_Batch__c,
                   Batch_Study_Program__c, Test_Schedule__c
            FROM Opportunity
            WHERE Name LIKE '%/REG/%'
            LIMIT 1
        ];
        Opportunity oldOpp = opp.clone(false, true, false, false);
        Map<Id, Opportunity> oldMap = new Map<Id, Opportunity>{ opp.Id => oldOpp };

        Test.startTest();
        OpportunityBatchStudyProgramController.handleBatchStudyProgram(
            new List<Opportunity>{ opp }, oldMap
        );
        Test.stopTest();

        Opportunity after = [
            SELECT Id, Name, Batch_Study_Program__c, Test_Schedule__c
            FROM Opportunity WHERE Id = :opp.Id
        ];
        System.assertNotEquals(null, after.Batch_Study_Program__c);
        System.assert(after.Name.contains('/REG/'));
    }
}