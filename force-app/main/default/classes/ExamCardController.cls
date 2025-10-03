public with sharing class ExamCardController {
    public String studentName { get; set; }
    public String testId { get; set; }
    public String registrationId { get; set; }
    public String testSchedule { get; set; }
    public String photoUrl { get; set; }

    public ExamCardController(ApexPages.StandardController stdCtrl) {

        Id oppId = stdCtrl.getId();

        // Fetch Opportunity for Registration ID
        Opportunity opp = [
            SELECT Id, Name, StageName
            FROM Opportunity
            WHERE Id = :oppId
            LIMIT 1
        ];
        registrationId = opp.Name;


        // Fetch Test Information
        List<Test_Information__c> tiList = [
            SELECT Id, Name, Applicant_Name__c, Test_Schedule__c
            FROM Test_Information__c
            WHERE Application_Progress__c = :oppId
            LIMIT 1
        ];
        if (!tiList.isEmpty()) {
            Test_Information__c ti = tiList[0];
            studentName = ti.Applicant_Name__c;
            testId = ti.Name;
            if (ti.Test_Schedule__c != null) {
                testSchedule = ti.Test_Schedule__c.format(); 
            }
        }

        // Fetch Pas Foto 3x4 document
        List<Account_Document__c> docs = [
            SELECT Id, Document_Link__c
            FROM Account_Document__c
            WHERE Application_Progress__c = :oppId
            AND Document_Type__c = 'Pas Foto 3x4'
            LIMIT 1
        ];
        if (!docs.isEmpty()) {
            String link = docs[0].Document_Link__c;
            photoUrl = extractFileUrl(link);
        }
    }

    private static String extractFileUrl(String link) {
        if (String.isBlank(link)) return null;

        Matcher m = Pattern.compile('([a-zA-Z0-9]{15,18})').matcher(link);
        while (m.find()) {
            String idCandidate = m.group(1);

            // Get base domain of the current org
            String baseUrl = System.Url.getOrgDomainUrl().toExternalForm();

            // Case 1: ContentVersion Id (068)
            if (idCandidate.startsWith('068')) {
                return baseUrl + '/sfc/servlet.shepherd/version/download/' + idCandidate;
            }

            // Case 2: ContentDocument Id (069)
            if (idCandidate.startsWith('069')) {
                return baseUrl + '/sfc/servlet.shepherd/document/download/' + idCandidate;
            }
        }

        // fallback (if already a public URL)
        return link;
    }
}