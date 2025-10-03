@IsTest(SeeAllData=false)
private class SendTestCardControllerTest {

    // ========= Utilities =========
    private static void putIfCreatable(SObject sobj, Schema.DescribeSObjectResult d, String field, Object value) {
        Map<String, Schema.SObjectField> fmap = d.fields.getMap();
        if (fmap.containsKey(field)) {
            Schema.DescribeFieldResult fd = fmap.get(field).getDescribe();
            if (fd.isCreateable()) {
                sobj.put(field, value);
            }
        }
    }

    private static Id getPersonAccountRtId() {
        List<RecordType> rts = [
            SELECT Id, Name, SObjectType, IsPersonType
            FROM RecordType
            WHERE SObjectType = 'Account' AND IsPersonType = true
            LIMIT 1
        ];
        return rts.isEmpty() ? null : rts[0].Id;
    }

    private static Account makePersonAccount(String name, String email) {
        Id paRtId = getPersonAccountRtId();
        System.assertNotEquals(null, paRtId,
            'This org must have Person Accounts enabled for this test to pass.');
        Account a = new Account(
            RecordTypeId = paRtId,
            LastName     = name,
            PersonEmail  = email
        );
        insert a;
        return a;
    }

    // ========= Campus__c =========
    private static SObject makeCampus() {
        SObject campus = (SObject) Type.forName(null, 'Campus__c').newInstance();
        Schema.DescribeSObjectResult d = Campus__c.SObjectType.getDescribe();

        campus.put('Name', 'Main Campus');
        // Required in your org:
        putIfCreatable(campus, d, 'Campus_Code__c', 'MAIN');

        // Common optional/required fields (safe if absent or read-only)
        putIfCreatable(campus, d, 'Is_Active__c', true);
        putIfCreatable(campus, d, 'City__c', 'Jakarta');
        putIfCreatable(campus, d, 'Country__c', 'ID');

        insert campus;
        return campus;
    }

    // ========= Master_Intake__c (now ties to Campus) =========
    private static SObject makeIntake(Id campusId) {
        SObject intake = (SObject) Type.forName(null, 'Master_Intake__c').newInstance();
        Schema.DescribeSObjectResult d = Master_Intake__c.SObjectType.getDescribe();

        intake.put('Name', '2025/2026 - Ganjil');

        // Satisfy typical lookup filters:
        putIfCreatable(intake, d, 'Is_Active__c', true);
        putIfCreatable(intake, d, 'Campus__c', campusId);           // must match Opp.Campus__c
        putIfCreatable(intake, d, 'Intake_Code__c', 'INT-GJ-2526');

        // If your org filters by date range, these help (skipped if read-only):
        putIfCreatable(intake, d, 'Start_Date__c', Date.today().addDays(7));
        putIfCreatable(intake, d, 'End_Date__c',   Date.today().addDays(60));

        insert intake;
        return intake;
    }

    // ========= Study_Program__c =========
    private static SObject makeStudyProgram(Id campusId) {
        SObject sp = (SObject) Type.forName(null, 'Study_Program__c').newInstance();
        Schema.DescribeSObjectResult d = Study_Program__c.SObjectType.getDescribe();

        sp.put('Name', 'Teknik Informatika');

        // Satisfy possible lookup filter and requireds:
        putIfCreatable(sp, d, 'Campus__c', campusId);
        putIfCreatable(sp, d, 'Program_Code__c', 'TI');
        putIfCreatable(sp, d, 'Is_Active__c', true);
        putIfCreatable(sp, d, 'Tuition_Fee__c', 10000000);

        insert sp;
        return sp;
    }

    // ========= Opportunity =========
    private static Opportunity makeOpportunity(
        Account acc, Id spId, Id intakeId, Id campusId,
        Boolean generatedFlag, String stage
    ) {
        Opportunity opp = new Opportunity(
            Name                    = 'APP-0001',
            AccountId               = acc.Id,
            StageName               = stage, // assumes 'Registration' & 'Test Card Sent' exist
            CloseDate               = Date.today().addDays(30),
            Test_Schedule__c        = System.now().addDays(3),
            Test_Card_Generated__c  = generatedFlag,
            Study_Program__c        = spId,
            Master_Intake__c        = intakeId,
            Campus__c               = campusId
        );
        insert opp;
        return opp;
    }

    // ========= Files =========
    private static void attachTestCardPdfToOpp(Opportunity opp) {
        String expectedTitle = 'TestCard_' + opp.Name;

        ContentVersion cv = new ContentVersion();
        cv.Title        = expectedTitle;
        cv.PathOnClient = expectedTitle + '.pdf';
        cv.VersionData  = Blob.valueOf('fake-pdf-binary');
        insert cv;

        cv = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];
        insert new ContentDocumentLink(
            ContentDocumentId = cv.ContentDocumentId,
            LinkedEntityId    = opp.Id,
            ShareType         = 'V'
        );
    }

    // ================== TESTS ==================

    @IsTest
    static void test_success_sendsEmail_and_updatesStage() {
        Account acc     = makePersonAccount('Raka Tester', 'raka.tester@example.com');
        SObject campus  = makeCampus();
        SObject intake  = makeIntake((Id)campus.get('Id'));   // pass campus
        SObject sp      = makeStudyProgram((Id)campus.get('Id'));

        Opportunity opp = makeOpportunity(
            acc, (Id) sp.get('Id'), (Id) intake.get('Id'), (Id) campus.get('Id'),
            /*generated*/ true, /*stage*/ 'Registration'
        );

        attachTestCardPdfToOpp(opp);

        Test.startTest();
        String result = SendTestCardController.sendTestCardEmail(opp.Id);
        Test.stopTest();

        System.assertEquals('success', result, 'Expected success result');

        Opportunity reloaded = [SELECT StageName FROM Opportunity WHERE Id = :opp.Id];
        System.assertEquals('Test Card Sent', reloaded.StageName);
    }

    @IsTest
    static void test_guard_generate_before_send() {
        Account acc     = makePersonAccount('NoGen User', 'nogen@example.com');
        SObject campus  = makeCampus();
        SObject intake  = makeIntake((Id)campus.get('Id'));
        SObject sp      = makeStudyProgram((Id)campus.get('Id'));

        Opportunity opp = makeOpportunity(
            acc, (Id) sp.get('Id'), (Id) intake.get('Id'), (Id) campus.get('Id'),
            /*generated*/ false, /*stage*/ 'Registration'
        );

        Test.startTest();
        String result = SendTestCardController.sendTestCardEmail(opp.Id);
        Test.stopTest();

        System.assertEquals('You must generate the Test Card before sending it.', result);
    }

    @IsTest
    static void test_missing_file_returns_message() {
        Account acc     = makePersonAccount('NoFile User', 'nofile@example.com');
        SObject campus  = makeCampus();
        SObject intake  = makeIntake((Id)campus.get('Id'));
        SObject sp      = makeStudyProgram((Id)campus.get('Id'));

        Opportunity opp = makeOpportunity(
            acc, (Id) sp.get('Id'), (Id) intake.get('Id'), (Id) campus.get('Id'),
            /*generated*/ true, /*stage*/ 'Registration'
        );

        // Intentionally no attachment

        Test.startTest();
        String result = SendTestCardController.sendTestCardEmail(opp.Id);
        Test.stopTest();

        System.assertEquals('No Test Card file found for this application.', result);
    }

    @IsTest
    static void test_missing_email_returns_message() {
        Account acc = makePersonAccount('No Email User', null);
        SObject campus  = makeCampus();
        SObject intake  = makeIntake((Id)campus.get('Id'));
        SObject sp      = makeStudyProgram((Id)campus.get('Id'));

        Opportunity opp = makeOpportunity(
            acc, (Id) sp.get('Id'), (Id) intake.get('Id'), (Id) campus.get('Id'),
            /*generated*/ true, /*stage*/ 'Registration'
        );

        attachTestCardPdfToOpp(opp);

        Test.startTest();
        String result = SendTestCardController.sendTestCardEmail(opp.Id);
        Test.stopTest();

        System.assertEquals('Applicant email is missing', result);
    }
}