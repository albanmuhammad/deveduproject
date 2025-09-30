public with sharing class GenerateTestCard {
    
    @AuraEnabled
    public static String createTestCardPdf(Id oppId) {
        System.debug('⚡ START createTestCardPdf for oppId=' + oppId);
        try {
            Opportunity opp = [
                SELECT Id, Name, Account.Name, CloseDate
                FROM Opportunity
                WHERE Id = :oppId
                LIMIT 1
            ];
            System.debug('⚡ Found Opportunity: ' + opp);

            PageReference pdfPage = Page.ExamCard; // check this name
            pdfPage.getParameters().put('id', opp.Id);
            Blob pdfBlob = pdfPage.getContentAsPDF();
            System.debug('⚡ PDF Generated, size=' + pdfBlob.size());

            ContentVersion cv = new ContentVersion();
            cv.Title = 'TestCard_' + opp.Name;
            cv.PathOnClient = 'TestCard_' + opp.Name + '.pdf';
            cv.VersionData = pdfBlob;
            insert cv;

            Id contentDocId = [
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

            System.debug('⚡ File Created and Linked Successfully');
            return 'File Created Success';
        } catch (Exception e) {
            System.debug('⚡ ERROR: ' + e.getMessage() + ' - ' + e.getStackTraceString());
            return 'Error: ' + e.getMessage();
        }
    }

}
