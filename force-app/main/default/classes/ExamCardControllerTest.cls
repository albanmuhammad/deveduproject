@IsTest
private class ExamCardControllerTest {

    // Utility: create a minimal Account + Opportunity you can use in StandardController
    private static Opportunity makeOpp() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        Opportunity opp = new Opportunity(
            Name      = 'REG-0001',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            AccountId = acc.Id
        );
        insert opp;
        return opp;
    }

    // Utility: upsert a Test_Information__c record linked to the Opportunity
    private static Test_Information__c makeTestInfo(Id oppId, Datetime whenDt) {
        Test_Information__c ti = new Test_Information__c(
            Application_Progress__c  = oppId,
            Test_Schedule__c         = whenDt
            // remove Applicant_Name__c because it’s not writeable
        );
        insert ti;

        // Re-query to get the system-populated fields like Name, Applicant_Name__c (if formula/lookup)
        ti = [
            SELECT Id, Name, Applicant_Name__c, Test_Schedule__c
            FROM Test_Information__c
            WHERE Id = :ti.Id
        ];
        return ti;
    }


    // Utility: create an Account_Document__c linked to the Opportunity
    private static Account_Document__c makeDoc(Id oppId, String linkVal) {
        Account_Document__c ad = new Account_Document__c(
            Application_Progress__c = oppId,
            Document_Type__c        = 'Pas Foto 3x4', // matches controller filter
            Document_Link__c        = linkVal
        );
        insert ad;
        return ad;
    }

    @IsTest
    static void test_HappyPath_VersionId068() {
        // Arrange
        Opportunity opp = makeOpp();
        Datetime dt = Datetime.newInstance(2025, 1, 2, 9, 30, 0);
        Test_Information__c ti = makeTestInfo(opp.Id, dt);
        // Fake a link that contains a ContentVersion Id (18 chars, starts with 068)
        String fakeVersionId = '068000000000000AAA';
        makeDoc(opp.Id, 'See File: ' + fakeVersionId);

        // Act
        ApexPages.StandardController std = new ApexPages.StandardController(opp);
        ExamCardController ctrl = new ExamCardController(std);

        // Assert (Opportunity / Registration)
        System.assertEquals('REG-0001', ctrl.registrationId, 'RegistrationId should be the Opp Name');

        // Assert (Test Info)
        System.assertEquals('Jane Doe', ctrl.studentName, 'Student name (Applicant_Name__c) mismatch');
        System.assertEquals(ti.Name, ctrl.testId, 'Test ID (TI.Name) mismatch');
        System.assertEquals(dt.format(), ctrl.testSchedule, 'Formatted Test_Schedule__c mismatch');

        // Assert (Photo URL from 068…)
        String base = System.Url.getOrgDomainUrl().toExternalForm();
        String expected = base + '/sfc/servlet.shepherd/version/download/' + fakeVersionId;
        System.assertEquals(expected, ctrl.photoUrl, 'Photo URL should use version/download for 068 ids');
    }

    @IsTest
    static void test_ContentDocumentId069() {
        // Arrange
        Opportunity opp = makeOpp();
        Datetime dt = Datetime.newInstance(2025, 3, 15, 14, 0, 0);
        makeTestInfo(opp.Id, dt);
        // Fake a link that contains a ContentDocument Id (starts with 069)
        String fakeDocId = '069000000000000AAA';
        makeDoc(opp.Id, 'Ref=' + fakeDocId);

        // Act
        ApexPages.StandardController std = new ApexPages.StandardController(opp);
        ExamCardController ctrl = new ExamCardController(std);

        // Assert (Photo URL from 069…)
        String base = System.Url.getOrgDomainUrl().toExternalForm();
        String expected = base + '/sfc/servlet.shepherd/document/download/' + fakeDocId;
        System.assertEquals(expected, ctrl.photoUrl, 'Photo URL should use document/download for 069 ids');
    }

    @IsTest
    static void test_Fallback_NoMatchingId_And_NoDoc() {
        // Case A: Doc exists but link has no 068/069 id → fallback to raw link
        Opportunity oppA = makeOpp();
        makeTestInfo(oppA.Id, Datetime.now());
        String publicUrl = 'https://cdn.example.com/files/photo.jpg';
        makeDoc(oppA.Id, publicUrl);

        ApexPages.StandardController stdA = new ApexPages.StandardController(oppA);
        ExamCardController ctrlA = new ExamCardController(stdA);
        System.assertEquals(publicUrl, ctrlA.photoUrl, 'When no 068/069 id is found, link should be returned as-is');

        // Case B: No Account_Document__c at all → photoUrl should be null
        Opportunity oppB = makeOpp();
        makeTestInfo(oppB.Id, Datetime.now());

        ApexPages.StandardController stdB = new ApexPages.StandardController(oppB);
        ExamCardController ctrlB = new ExamCardController(stdB);
        System.assertEquals(null, ctrlB.photoUrl, 'Without a matching document, photoUrl should be null');
    }
}