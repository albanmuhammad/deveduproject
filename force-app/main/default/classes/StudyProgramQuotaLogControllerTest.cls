@IsTest
private class StudyProgramQuotaLogControllerTest {

    private static Batch_Study_Program__c makeBsp() {
        // We need a Study_Program_Intake__c to hang on BSP for the controller query
        Study_Program_Intake__c spi = new Study_Program_Intake__c(
            Application_Fee__c=20000000
        );
        insert spi;
        Batch_Study_Program__c bsp = new Batch_Study_Program__c(
            Name='BSP-1', Study_Program_Intake__c=spi.Id
        );
        insert bsp;
        return bsp;
    }

    @IsTest
    static void createsPlusOneWhenBspFilled() {
        Account a = new Account(Name='AC-1');
        insert a;

        Opportunity oldV = new Opportunity(
            Name='O1',
            AccountId=a.Id,
            StageName='Prospecting',
            CloseDate=Date.today().addDays(5)
        );
        insert oldV;

        Opportunity newV = oldV.clone(false, true, false, false);
        newV.Batch_Study_Program__c = makeBsp().Id;

        Test.startTest();
        StudyProgramQuotaLogController.createQuotaLogs(
            new List<Opportunity>{ newV },
            new Map<Id, Opportunity>{ oldV.Id => oldV }
        );
        Test.stopTest();

        Integer cnt = [SELECT COUNT() FROM Study_Program_Quota_Log__c WHERE Application_Progress__c = :oldV.Id];
        System.assertEquals(1, cnt, 'Should create +1 log when BSP is newly filled');
    }

    @IsTest
    static void createsMinusOneWhenClosedLost() {
        Account a = new Account(Name='AC-2');
        insert a;

        Batch_Study_Program__c bsp = makeBsp();

        Opportunity oldV = new Opportunity(
            Name='O2',
            AccountId=a.Id,
            StageName='Prospecting',
            CloseDate=Date.today().addDays(5),
            Batch_Study_Program__c=bsp.Id
        );
        insert oldV;

        Opportunity newV = oldV.clone(false, true, false, false);
        newV.StageName='Closed Lost';

        Test.startTest();
        StudyProgramQuotaLogController.createQuotaLogs(
            new List<Opportunity>{ newV },
            new Map<Id, Opportunity>{ oldV.Id => oldV }
        );
        Test.stopTest();

        // Expect 1 (from initial fill) + 1 (−1 log on Closed Lost) if you also run handler on insert.
        // Here we only invoked controller directly once, so just 1 record for Closed Lost.
        Integer cnt = [SELECT COUNT() FROM Study_Program_Quota_Log__c WHERE Application_Progress__c = :oldV.Id];
        System.assertEquals(1, cnt, 'Should create −1 log when moved to Closed Lost');
    }
}