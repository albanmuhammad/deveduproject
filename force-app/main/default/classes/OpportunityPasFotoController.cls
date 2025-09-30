public with sharing class OpportunityPasFotoController {
    @AuraEnabled(cacheable=true)
    public static String getPasFotoVersionId(Id recordId) {
        List<ContentDocumentLink> links = [
            SELECT ContentDocument.LatestPublishedVersionId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :recordId
              AND ContentDocument.Title LIKE 'Pas Foto 3x4%'
            ORDER BY ContentDocument.CreatedDate DESC
            LIMIT 1
        ];
        if (!links.isEmpty()) {
            return (String) links[0].ContentDocument.LatestPublishedVersionId;
        }
        return null;
    }
}
