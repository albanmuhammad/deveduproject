@isTest
public class OpportunityPasFotoControllerTest {

    @isTest
    static void testGetPasFotoVersionId_Found() {
        // Create an Account (required for Opportunity)
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        // Create an Opportunity
        Opportunity opp = new Opportunity(
            Name = 'Test Opp',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(7),
            AccountId = acc.Id
        );
        insert opp;

        // Create a ContentVersion (this creates ContentDocument automatically)
        ContentVersion cv = new ContentVersion(
            Title = 'Pas Foto 3x4 - Test',
            PathOnClient = 'TestPhoto.png',
            VersionData = Blob.valueOf('fake image content')
        );
        insert cv;

        // Query ContentDocumentId
        Id contentDocId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;

        // Link ContentDocument to Opportunity
        ContentDocumentLink cdl = new ContentDocumentLink(
            ContentDocumentId = contentDocId,
            LinkedEntityId = opp.Id,
            ShareType = 'V'
        );
        insert cdl;

        // Call the method
        Test.startTest();
        String versionId = OpportunityPasFotoController.getPasFotoVersionId(opp.Id);
        Test.stopTest();

        System.assertNotEquals(null, versionId, 'Should return a version Id when pas foto exists');
    }

    @isTest
    static void testGetPasFotoVersionId_NotFound() {
        // Create Account + Opp
        Account acc = new Account(Name = 'No File Account');
        insert acc;

        Opportunity opp = new Opportunity(
            Name = 'Opp No File',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(7),
            AccountId = acc.Id
        );
        insert opp;

        // Call without attaching any pas foto
        Test.startTest();
        String versionId = OpportunityPasFotoController.getPasFotoVersionId(opp.Id);
        Test.stopTest();

        System.assertEquals(null, versionId, 'Should return null if no pas foto linked');
    }
}