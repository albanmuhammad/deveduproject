public with sharing class AccountDocumentController {
    public class InitResp {
        @AuraEnabled public Boolean isSchool;
        @AuraEnabled public String opportunityName;
        @AuraEnabled public Map<String, DocStatus> statusByType;
    }
    public class DocStatus {
        @AuraEnabled public Boolean uploaded;
        @AuraEnabled public Boolean verified;
        @AuraEnabled public String contentDocumentId;
        @AuraEnabled public String documentLink;
    }

    @AuraEnabled
    public static InitResp getInitData(Id accountId, Id opportunityId, List<String> documentTypes) {
        InitResp out = new InitResp();
        out.isSchool = false;
        out.opportunityName = '';
        out.statusByType = new Map<String, DocStatus>();
        if (opportunityId != null) {
            Opportunity o = [
                SELECT Id, Name, RecordType.Name
                FROM Opportunity
                WHERE Id = :opportunityId
                LIMIT 1
            ];
            out.opportunityName = o.Name;
            out.isSchool = (o.RecordType != null && o.RecordType.Name == 'School');
        }
        if (accountId == null || documentTypes == null || documentTypes.isEmpty()) {
            return out;
        }
        List<Account_Document__c> docs = new List<Account_Document__c>();
        if (opportunityId != null) {
            docs.addAll([
                SELECT Id, Document_Type__c, Verified__c, Document_Link__c, Application_Progress__c, Account__c
                FROM Account_Document__c
                WHERE Account__c = :accountId
                AND Document_Type__c IN :documentTypes
                AND Application_Progress__c = :opportunityId
            ]);
            docs.addAll([
                SELECT Id, Document_Type__c, Verified__c, Document_Link__c, Application_Progress__c, Account__c
                FROM Account_Document__c
                WHERE Account__c = :accountId
                AND Document_Type__c IN :documentTypes
                AND Application_Progress__c = NULL
            ]);
        } else {
            docs.addAll([
                SELECT Id, Document_Type__c, Verified__c, Document_Link__c, Application_Progress__c, Account__c
                FROM Account_Document__c
                WHERE Account__c = :accountId
                AND Document_Type__c IN :documentTypes
                AND Application_Progress__c = NULL
            ]);
        }
        Map<Id, String> fileByDoc = new Map<Id, String>();
        if (!docs.isEmpty()) {
            Set<Id> docIds = new Map<Id, Account_Document__c>(docs).keySet();

            // Query di luar loop; ambil link terbaru per dokumen
            List<ContentDocumentLink> links = [
                SELECT ContentDocumentId, LinkedEntityId
                FROM ContentDocumentLink
                WHERE LinkedEntityId IN :docIds
            ];

            // Isi hanya sekali per LinkedEntityId (karena sudah diurutkan DESC -> yang pertama = terbaru)
            for (ContentDocumentLink l : links) {
                if (!fileByDoc.containsKey(l.LinkedEntityId)) {
                    fileByDoc.put(l.LinkedEntityId, l.ContentDocumentId);
                }
            }
        }
        Map<String, Account_Document__c> pick = new Map<String, Account_Document__c>();
        for (Account_Document__c d : docs) {
            if (!pick.containsKey(d.Document_Type__c)) {
                pick.put(d.Document_Type__c, d);
            } else if (opportunityId != null
                       && pick.get(d.Document_Type__c).Application_Progress__c == null
                       && d.Application_Progress__c == opportunityId) {
                pick.put(d.Document_Type__c, d);
            }
        }
        for (String t : documentTypes) out.statusByType.put(t, new DocStatus());
        for (String t : pick.keySet()) {
            Account_Document__c d = pick.get(t);
            DocStatus st = new DocStatus();
            st.verified = d.Verified__c;
            st.uploaded = fileByDoc.containsKey(d.Id);
            st.contentDocumentId = fileByDoc.get(d.Id);
            st.documentLink = d.Document_Link__c;
            if (st.documentLink == null && st.contentDocumentId != null) {
                st.documentLink = '/lightning/r/ContentDocument/' + st.contentDocumentId + '/view';
            }
            out.statusByType.put(t, st);
        }
        return out;
    }

    @AuraEnabled
    public static void saveAccountDocument(Id accountId, Id opportunityId, Id initialParentId, String documentType, Id contentDocumentId) {
        if (accountId == null) {
            throw new AuraHandledException('Account is required (Application Progress must have an Account).');
        }
        if (String.isBlank(documentType) || contentDocumentId == null) {
            throw new AuraHandledException('Missing required parameters.');
        }

        // Find or create the Account_Document__c that represents this slot
        Account_Document__c doc = getOrCreateAccountDocument(accountId, opportunityId, documentType);

        // --- NEW: If this slot is NOT verified, remove any previously attached ContentDocuments
        //           so we don't keep stale files around.
        if (doc.Verified__c == false) {
            // Collect all ContentDocuments currently linked to this Account_Document__c
            List<ContentDocumentLink> oldLinks = [
                SELECT ContentDocumentId
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :doc.Id
            ];
            Set<Id> oldDocIds = new Set<Id>();
            for (ContentDocumentLink l : oldLinks) {
                // Just in case the same documentId gets passed again (rare), exclude the incoming one.
                if (l.ContentDocumentId != contentDocumentId) {
                    oldDocIds.add(l.ContentDocumentId);
                }
            }
            if (!oldDocIds.isEmpty()) {
                // Deleting ContentDocument deletes all its links (including from the Opportunity “Files” related list)
                delete [SELECT Id FROM ContentDocument WHERE Id IN :oldDocIds];
            }
            // Clear any stale link URL
            doc.Document_Link__c = null;
            update doc;
        }

        // Link the new upload to the Account_Document__c
        insert new ContentDocumentLink(
            ContentDocumentId = contentDocumentId,
            LinkedEntityId    = doc.Id,
            ShareType         = 'V',
            Visibility        = 'AllUsers'
        );

        // Build a title based on AP name for nicer file naming
        String apName = '';
        if (opportunityId != null) {
            apName = [SELECT Name FROM Opportunity WHERE Id = :opportunityId LIMIT 1].Name;
        }
        String newFileTitle = String.isBlank(apName) ? documentType : (documentType + '_' + apName);

        // Rename ContentDocument + latest ContentVersion
        ContentDocument cd = [SELECT Id, Title FROM ContentDocument WHERE Id = :contentDocumentId LIMIT 1];
        cd.Title = newFileTitle;
        update cd;

        ContentVersion cv = [
            SELECT Id, Title
            FROM ContentVersion
            WHERE ContentDocumentId = :contentDocumentId
            ORDER BY VersionNumber DESC
            LIMIT 1
        ];
        cv.Title = newFileTitle;
        update cv;

        // Update the logical document record
        String docName = String.isBlank(apName) ? documentType : (documentType + ' ' + apName);
        doc.Verified__c = false;
        doc.Document_Link__c = '/lightning/r/ContentDocument/' + contentDocumentId + '/view';
        doc.Name = docName;
        update doc;
    }

    @AuraEnabled
    public static void verifyAccountDocument(Id accountId, Id opportunityId, String documentType, Boolean verified) {
        Account_Document__c doc = findDoc(accountId, opportunityId, documentType);
        if (doc == null) {
            throw new AuraHandledException('No Account Document found to verify for type "' + documentType + '".');
        }
        doc.Verified__c = (verified == true);
        update doc;
    }

    @AuraEnabled
    public static void deleteAccountDocument(Id accountId, Id opportunityId, String documentType) {
        Account_Document__c doc = findDoc(accountId, opportunityId, documentType);
        if (doc == null) {
            throw new AuraHandledException('Nothing to delete for type "' + documentType + '".');
        }
        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :doc.Id
        ];
        Set<Id> contentIds = new Set<Id>();
        for (ContentDocumentLink l : links) contentIds.add(l.ContentDocumentId);
        if (!contentIds.isEmpty()) {
            delete [SELECT Id FROM ContentDocument WHERE Id IN :contentIds];
        }
        delete doc;
    }

    private static Account_Document__c getOrCreateAccountDocument(Id accountId, Id opportunityId, String documentType) {
        Account_Document__c existing = findDoc(accountId, opportunityId, documentType);
        if (existing != null) return existing;
        Account_Document__c fresh = new Account_Document__c(
            Account__c = accountId,
            Application_Progress__c = opportunityId,
            Document_Type__c = documentType,
            Verified__c = false
        );
        insert fresh;
        return fresh;
    }

    private static Account_Document__c findDoc(Id accountId, Id opportunityId, String documentType) {
        if (accountId == null || String.isBlank(documentType)) return null;
        if (opportunityId != null) {
            List<Account_Document__c> exact = [
                SELECT Id, Verified__c, Document_Link__c, Application_Progress__c, Account__c, Document_Type__c, Name
                FROM Account_Document__c
                WHERE Account__c = :accountId
                AND Document_Type__c = :documentType
                AND Application_Progress__c = :opportunityId
                LIMIT 1
            ];
            if (!exact.isEmpty()) return exact[0];
            List<Account_Document__c> legacy = [
                SELECT Id, Verified__c, Document_Link__c, Application_Progress__c, Account__c, Document_Type__c, Name
                FROM Account_Document__c
                WHERE Account__c = :accountId
                AND Document_Type__c = :documentType
                AND Application_Progress__c = NULL
                LIMIT 1
            ];
            if (!legacy.isEmpty()) return legacy[0];
            return null;
        } else {
            List<Account_Document__c> onlyNull = [
                SELECT Id, Verified__c, Document_Link__c, Application_Progress__c, Account__c, Document_Type__c, Name
                FROM Account_Document__c
                WHERE Account__c = :accountId
                AND Document_Type__c = :documentType
                AND Application_Progress__c = NULL
                LIMIT 1
            ];
            if (!onlyNull.isEmpty()) return onlyNull[0];
            return null;
        }
    }
}