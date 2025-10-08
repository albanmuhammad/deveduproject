public with sharing class QrFileController {
    @AuraEnabled
    public static Id savePng(Id parentId, String base64Png, String fileName) {
        if (String.isBlank(parentId) || String.isBlank(base64Png)) {
            throw new AuraHandledException('parentId/base64Png wajib diisi');
        }
        if (String.isBlank(fileName)) fileName = 'qr.png';

        Blob body = EncodingUtil.base64Decode(base64Png);

        ContentVersion cv = new ContentVersion();
        cv.Title = fileName;
        cv.PathOnClient = fileName;
        cv.VersionData = body;
        insert cv;

        cv = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1];

        insert new ContentDocumentLink(
            ContentDocumentId = cv.ContentDocumentId,
            LinkedEntityId    = parentId,
            ShareType         = 'V',
            Visibility        = 'AllUsers'
        );
        return cv.ContentDocumentId;
    }
}