@isTest
private class AccountDocumentControllerTest {
    
    static void testGetInitData() {
        // Create test data
        Account acc = new Account(Name='Test Account');
        insert acc;
        
        Opportunity opp = new Opportunity(
            Name='Test Opportunity',
            AccountId=acc.Id,
            StageName='Prospecting',
            CloseDate=Date.today()
        );
        insert opp;
        
        // Create record type for School
        // RecordType rt = new RecordType(
        //     Name='University',
        //     SobjectType='Opportunity',
        //     DeveloperName='University'
        // );
        // insert rt;
        
        // Update opportunity with record type
        // opp.RecordTypeId = rt.Id;
        // update opp;
        
        // Create account documents
        Account_Document__c doc1 = new Account_Document__c(
            Account__c=acc.Id,
            Document_Type__c='ID',
            Application_Progress__c=opp.Id
        );
        Account_Document__c doc2 = new Account_Document__c(
            Account__c=acc.Id,
            Document_Type__c='Passport',
            Application_Progress__c=null
        );
        insert new List<Account_Document__c>{doc1, doc2};
        
        // Create content document and link
        ContentVersion cv = new ContentVersion(
            Title='Test Document',
            PathOnClient='test.pdf',
            VersionData=Blob.valueOf('Test Content')
        );
        insert cv;
        
        ContentDocumentLink cdl = new ContentDocumentLink(
            ContentDocumentId=cv.ContentDocumentId,
            LinkedEntityId=doc1.Id
        );
        insert cdl;
        
        // Test method
        List<String> docTypes = new List<String>{'ID', 'Passport'};
        AccountDocumentController.InitResp result = AccountDocumentController.getInitData(acc.Id, opp.Id, docTypes);
        
        // Assertions
        System.assertEquals(true, result.isSchool);
        System.assertEquals(opp.Name, result.opportunityName);
        System.assertEquals(2, result.statusByType.size());
        // System.assertTrue(result.statusByType.containsKey('ID'));
        // System.assertTrue(result.statusByType.containsKey('Passport'));
        
        // Verify ID document status
        AccountDocumentController.DocStatus idStatus = result.statusByType.get('ID');
        System.assertEquals(true, idStatus.verified);
        System.assertEquals(true, idStatus.uploaded);
        System.assertEquals(cv.ContentDocumentId, idStatus.contentDocumentId);
        System.assertNotEquals(null, idStatus.documentLink);
        
        // Verify Passport document status
        AccountDocumentController.DocStatus passportStatus = result.statusByType.get('Passport');
        System.assertEquals(false, passportStatus.verified);
        System.assertEquals(false, passportStatus.uploaded);
        System.assertEquals(null, passportStatus.contentDocumentId);
        System.assertEquals(null, passportStatus.documentLink);
    }

    @isTest
    static void testSaveAccountDocumentWithVerifiedSlot() {
        // Create test data
        Account acc = new Account(Name='Test Account');
        insert acc;
        
        Opportunity opp = new Opportunity(
            Name='Test Opportunity',
            AccountId=acc.Id,
            StageName='Prospecting',
            CloseDate=Date.today()
        );
        insert opp;
        
        // Create account document with verified=true
        Account_Document__c doc = new Account_Document__c(
            Account__c=acc.Id,
            Document_Type__c='ID',
            Application_Progress__c=opp.Id,
            Verified__c=true
        );
        insert doc;
        
        // Create content document
        ContentVersion cv = new ContentVersion(
            Title='Test Document',
            PathOnClient='test.pdf',
            VersionData=Blob.valueOf('Test Content')
        );
        insert cv;
        
        // Test method - should not delete existing documents when verified
        AccountDocumentController.saveAccountDocument(
            acc.Id,
            opp.Id,
            doc.Id,
            'ID',
            cv.ContentDocumentId
        );
        
        // Verify the document was linked correctly
        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId 
            FROM ContentDocumentLink 
            WHERE LinkedEntityId = :doc.Id
        ];
        System.assertEquals(1, links.size());
        System.assertEquals(cv.ContentDocumentId, links[0].ContentDocumentId);
    }
    
    @isTest
    static void testSaveAccountDocumentNullAccountId() {
        // Test with null account id
        try {
            AccountDocumentController.saveAccountDocument(
                null,
                null,
                null,
                'ID',
                null
            );
            System.assert(false, 'Expected AuraHandledException was not thrown');
        } catch (AuraHandledException e) {
            System.assertEquals('Account is required (Application Progress must have an Account).', e.getMessage());
        }
    }
    
    @isTest
    static void testSaveAccountDocumentMissingParams() {
        // Create test data
        Account acc = new Account(Name='Test Account');
        insert acc;
        
        // Test with missing document type
        try {
            AccountDocumentController.saveAccountDocument(
                acc.Id,
                null,
                null,
                null,
                null
            );
            System.assert(false, 'Expected AuraHandledException was not thrown');
        } catch (AuraHandledException e) {
            System.assertEquals('Missing required parameters.', e.getMessage());
        }
        
        // Test with missing content document id
        try {
            AccountDocumentController.saveAccountDocument(
                acc.Id,
                null,
                null,
                'ID',
                null
            );
            System.assert(false, 'Expected AuraHandledException was not thrown');
        } catch (AuraHandledException e) {
            System.assertEquals('Missing required parameters.', e.getMessage());
        }
    }
    
    @isTest
    static void testSaveAccountDocumentWithExistingDocument() {
        // Create test data
        Account acc = new Account(Name='Test Account');
        insert acc;
        
        Opportunity opp = new Opportunity(
            Name='Test Opportunity',
            AccountId=acc.Id,
            StageName='Prospecting',
            CloseDate=Date.today()
        );
        insert opp;
        
        // Create account document
        Account_Document__c doc = new Account_Document__c(
            Account__c=acc.Id,
            Document_Type__c='ID',
            Application_Progress__c=opp.Id,
            Verified__c=false
        );
        insert doc;
        
        // Create existing content document
        ContentVersion existingCv = new ContentVersion(
            Title='Existing Document',
            PathOnClient='existing.pdf',
            VersionData=Blob.valueOf('Existing Content')
        );
        insert existingCv;
        
        // Create new content document
        ContentVersion newCv = new ContentVersion(
            Title='New Document',
            PathOnClient='new.pdf',
            VersionData=Blob.valueOf('New Content')
        );
        insert newCv;
        
        // Link existing document to account document
        ContentDocumentLink existingLink = new ContentDocumentLink(
            ContentDocumentId=existingCv.ContentDocumentId,
            LinkedEntityId=doc.Id
        );
        insert existingLink;
        
        // Save new document - should delete existing document since slot is not verified
        AccountDocumentController.saveAccountDocument(
            acc.Id,
            opp.Id,
            doc.Id,
            'ID',
            newCv.ContentDocumentId
        );
        
        // Verify existing document was deleted
        List<ContentDocument> deletedDocs = [
            SELECT Id FROM ContentDocument WHERE Id = :existingCv.ContentDocumentId
        ];
        System.assertEquals(0, deletedDocs.size());
        
        // Verify new document is linked
        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId 
            FROM ContentDocumentLink 
            WHERE LinkedEntityId = :doc.Id
        ];
        System.assertEquals(1, links.size());
        System.assertEquals(newCv.ContentDocumentId, links[0].ContentDocumentId);
    }
}