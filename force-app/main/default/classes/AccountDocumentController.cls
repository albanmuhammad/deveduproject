public with sharing class AccountDocumentController {
    @AuraEnabled
    public static void saveAccountDocument(Id accountId, String documentType, Id contentDocumentId) {
        Account_Document__c doc = new Account_Document__c(
            Account__c = accountId,
            Document_Type__c = documentType
        );
        insert doc;

        ContentDocumentLink cdl = new ContentDocumentLink(
            ContentDocumentId = contentDocumentId,
            LinkedEntityId    = doc.Id,
            ShareType         = 'V',   
            Visibility        = 'AllUsers'
        );
        insert cdl;
    }
}
