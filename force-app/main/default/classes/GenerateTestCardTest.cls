@IsTest
private class GenerateTestCardTest {

    // ---------- Test data helpers ----------
    @testSetup
    static void seed() {
        insert new Account(Name = 'Test Student');
    }

    private static Account anyAccount() {
        return [SELECT Id, Name FROM Account LIMIT 1];
    }

    private static Opportunity makeOpp(Boolean photoVerified, String suffix) {
        Opportunity o = new Opportunity(
            Name      = 'REG-' + suffix,
            StageName = 'Prospecting',
            CloseDate = System.today().addDays(3),
            AccountId = anyAccount().Id
        );
        // use dynamic assignment so this compiles even if the field name varies between orgs
        o.put('Is_3x4_Photo_Verified__c', photoVerified);
        insert o;
        return o;
    }

    // ---------- 1) Early return when photo not verified ----------
    @IsTest
    static void rejectsWhenPhotoNotVerified() {
        Opportunity o = makeOpp(false, 'NV-001');

        Test.startTest();
        String res = GenerateTestCard.createTestCardPdf(o.Id);
        Test.stopTest();

        System.assertEquals(
            'Pas foto 3x4 must be verified before generating test card',
            res,
            'Should block generation when photo is not verified'
        );
    }

    // ---------- 2) Missing Opportunity -> caught error ----------
    @IsTest
    static void invalidId_hitsCatchEarly() {
        // Build a non-existent Opp Id (006 = Opportunity prefix)
        Id fakeOppId = Id.valueOf('006000000000000AAA');

        Test.startTest();
        String res = GenerateTestCard.createTestCardPdf(fakeOppId);
        Test.stopTest();

        System.assert(res.startsWith('Error:'), 'Should return an Error: message');
        System.assert(
            res.contains('List has no rows'),
            'Should mention no rows for assignment to SObject'
        );
    }

    // ---------- 3) Existing file path -> update & "File Updated Success" ----------
    @IsTest
    static void updatePath_preSeededDoc_alsoHitsRestriction_andIsCaught() {
        // Ensure the seam is enabled (in case someone changes the default later)
        GenerateTestCard.BYPASS_PDF_IN_TESTS = true;

        Opportunity o = makeOpp(true, 'EXIST-001');

        String expectedTitle = 'TestCard_' + o.Name;

        // Seed a ContentVersion so there is already a ContentDocument linked to the Opp
        ContentVersion seed = new ContentVersion(
            Title        = expectedTitle,
            PathOnClient = expectedTitle + '.pdf',
            VersionData  = Blob.valueOf('seed bytes')
        );
        insert seed;

        Id docId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :seed.Id].ContentDocumentId;

        insert new ContentDocumentLink(
            ContentDocumentId = docId,
            LinkedEntityId    = o.Id,
            ShareType         = 'V',
            Visibility        = 'AllUsers'
        );

        // Act
        Test.startTest();
        String res = GenerateTestCard.createTestCardPdf(o.Id);
        Test.stopTest();

        System.assertEquals('File Updated Success', res, 'Should update existing Test Card');

        // Optional: prove a newer version exists for the same ContentDocument
        Integer versions =
            [SELECT COUNT() FROM ContentVersion WHERE ContentDocumentId = :docId];
        System.assert(versions >= 2, 'Should have created a new version on update');
    }

    // ---------- 4) No existing file path -> create & "File Created Success" ----------
    @IsTest
    static void createPath_hitsGetContentRestriction_butIsCaught() {
        // Ensure the seam is enabled (in case someone changes the default later)
        GenerateTestCard.BYPASS_PDF_IN_TESTS = true;

        Opportunity o = makeOpp(true, 'CREATE-001');
        String expectedTitle = 'TestCard_' + o.Name;

        // Act
        Test.startTest();
        String res = GenerateTestCard.createTestCardPdf(o.Id);
        Test.stopTest();

        System.assertEquals('File Created Success', res, 'Should create a new Test Card');

        // Assert file linked to Opp
        ContentDocumentLink cdl = [
            SELECT Id, ContentDocument.Title, LinkedEntityId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :o.Id
            LIMIT 1
        ];
        System.assertEquals(expectedTitle, cdl.ContentDocument.Title, 'Title should match');

        // Assert Opp flag flipped
        Opportunity oAfter = [SELECT Test_Card_Generated__c FROM Opportunity WHERE Id = :o.Id];
        System.assertEquals(true, oAfter.get('Test_Card_Generated__c'), 'Flag should be set true');
    }
}