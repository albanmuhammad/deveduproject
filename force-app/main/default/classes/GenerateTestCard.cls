public with sharing class GenerateTestCard {

    // Seam so tests can bypass Visualforce PDF rendering
    @TestVisible private static Boolean BYPASS_PDF_IN_TESTS = true;

    @AuraEnabled
    public static String createTestCardPdf(Id oppId) {
        System.debug('⚡ START createTestCardPdf for oppId=' + oppId);
        try {
            Opportunity opp = [
                SELECT Id, Name, Account.Name, CloseDate, Is_3x4_Photo_Verified__c,
                       Test_Card_Generated__c
                FROM Opportunity
                WHERE Id = :oppId
                LIMIT 1
            ];
            System.debug('⚡ Found Opportunity: ' + opp);

            // Validate pas foto verification
            if (opp.Is_3x4_Photo_Verified__c != true) {
                return 'Pas foto 3x4 must be verified before generating test card';
            }

            // Build expected file title
            String expectedTitle = 'TestCard_' + opp.Name;

            // 🔹 Check if file already exists
            List<ContentDocumentLink> existingLinks = [
                SELECT ContentDocumentId, ContentDocument.Title
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :opp.Id
                AND ContentDocument.Title = :expectedTitle
                LIMIT 1
            ];

            Id contentDocId;
            if (!existingLinks.isEmpty()) {
                // File already exists → update with new version
                contentDocId = existingLinks[0].ContentDocumentId;

                PageReference pdfPage = Page.ExamCard;
                pdfPage.getParameters().put('id', opp.Id);

                Blob pdfBlob;
                if (Test.isRunningTest() && BYPASS_PDF_IN_TESTS) {
                    pdfBlob = Blob.valueOf('test-pdf');
                } else {
                    pdfBlob = pdfPage.getContentAsPDF();
                }

                ContentVersion newVersion = new ContentVersion();
                newVersion.ContentDocumentId = contentDocId;
                newVersion.Title = expectedTitle;
                newVersion.PathOnClient = expectedTitle + '.pdf';
                newVersion.VersionData = pdfBlob;
                insert newVersion;

                System.debug('⚡ Existing Test Card updated successfully');
                return 'File Updated Success';
            } else {
                // No file exists → create new one
                PageReference pdfPage = Page.ExamCard;
                pdfPage.getParameters().put('id', opp.Id);

                Blob pdfBlob;
                if (Test.isRunningTest() && BYPASS_PDF_IN_TESTS) {
                    pdfBlob = Blob.valueOf('test-pdf');
                } else {
                    pdfBlob = pdfPage.getContentAsPDF();
                }

                ContentVersion cv = new ContentVersion();
                cv.Title = expectedTitle;
                cv.PathOnClient = expectedTitle + '.pdf';
                cv.VersionData = pdfBlob;
                insert cv;

                contentDocId = [
                    SELECT ContentDocumentId
                    FROM ContentVersion
                    WHERE Id = :cv.Id
                ].ContentDocumentId;

                ContentDocumentLink cdl = new ContentDocumentLink();
                cdl.ContentDocumentId = contentDocId;
                cdl.LinkedEntityId = opp.Id;
                cdl.ShareType = 'V';
                cdl.Visibility = 'AllUsers';
                insert cdl;

                opp.Test_Card_Generated__c = true;
                update opp;

                System.debug('⚡ New Test Card created successfully');
                return 'File Created Success';
            }

        } catch (Exception e) {
            System.debug('⚡ ERROR: ' + e.getMessage());
            return 'Error: ' + e.getMessage();
        }
    }
}