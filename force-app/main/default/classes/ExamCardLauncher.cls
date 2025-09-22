public with sharing class ExamCardLauncher {
    public Id recordId { get; set; }

    public ExamCardLauncher(ApexPages.StandardController stdCtrl) {
        recordId = stdCtrl.getId();
    }

    public PageReference generateCard() {
        Opportunity opp = [
            SELECT Id, StageName
            FROM Opportunity
            WHERE Id = :recordId
            LIMIT 1
        ];

        if (opp.StageName == 'Registration') {
            opp.StageName = 'Test';
            update opp;
        }

        // Redirect to the PDF page
        PageReference pdfPage = Page.ExamCard; // your VF page name
        pdfPage.getParameters().put('id', recordId);
        return pdfPage;
    }
}
