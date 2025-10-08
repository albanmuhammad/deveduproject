@IsTest
private class TestInformationControllerTest {

    // Helper: create an Account that works with or without Person Accounts
    private static Account makeAccount() {
        List<RecordType> paRts = [
            SELECT Id, IsPersonType
            FROM RecordType
            WHERE SObjectType = 'Account' AND IsPersonType = true
            LIMIT 1
        ];

        Account acc = paRts.isEmpty()
            ? new Account(Name = 'Test Student Co.')
            : new Account(RecordTypeId = paRts[0].Id, LastName = 'Test Student');
        insert acc;
        return acc;
    }

    @testSetup
    static void setupData() {
        Account acc = makeAccount();

        Opportunity opp = new Opportunity(
            Name='Test Opp',
            StageName='Prospecting',
            CloseDate=Date.today().addDays(1),
            AccountId=acc.Id
        );
        insert opp;

        Date d = Date.today();
        Datetime noonToday = Datetime.newInstance(d.year(), d.month(), d.day(), 12, 0, 0);

        Test_Information__c ti = new Test_Information__c(
            Name='Test Info',
            Applicant__c=acc.Id,
            Application_Progress__c=opp.Id,
            Test_Schedule__c=noonToday,
            Is_Attend__c=false
        );
        insert ti;
    }

    @IsTest
    static void testGetTodaysTests() {
        Test.startTest();
        List<Test_Information__c> results = TestInformationController.getTodaysTests();
        Test.stopTest();

        System.assert(results.size() > 0, 'Should return at least one record');

        // We only assert on fields that are actually selected by the method
        Test_Information__c got = results[0];
        System.assertEquals('Test Info', got.Name);
        System.assertNotEquals(null, got.Test_Schedule__c, 'Test_Schedule__c should be selected');
        System.assertNotEquals(null, got.Application_Progress__c, 'Application_Progress__c should be selected');

        // If you still want to check Is_Attend__c, re-query by Id:
        Test_Information__c check = [
            SELECT Is_Attend__c
            FROM Test_Information__c
            WHERE Id = :got.Id
        ];
        System.assertEquals(false, check.Is_Attend__c, 'Attendance should initially be false');
    }

    @IsTest
    static void testUpdateAttendance() {
        Test_Information__c ti = [
            SELECT Id, Is_Attend__c
            FROM Test_Information__c
            LIMIT 1
        ];
        System.assertEquals(false, ti.Is_Attend__c);

        Test.startTest();
        String result = TestInformationController.updateAttendance(new List<Id>{ ti.Id });
        Test.stopTest();

        System.assertEquals('Success', result);

        ti = [
            SELECT Id, Is_Attend__c
            FROM Test_Information__c
            WHERE Id = :ti.Id
        ];
        System.assertEquals(true, ti.Is_Attend__c);
    }

    @IsTest
    static void testUpdateAttendanceNoIds() {
        Boolean threw = false;
        try {
            Test.startTest();
            TestInformationController.updateAttendance(new List<Id>());
            Test.stopTest();
        } catch (AuraHandledException e) {
            threw = true;
            // Don’t overfit the exact text; just ensure we got *an* AuraHandledException.
            System.assert(e.getMessage() != null && e.getMessage().length() > 0,
                          'Exception should include a message');
        }
        System.assertEquals(true, threw, 'Should throw when no IDs are provided');
    }
}