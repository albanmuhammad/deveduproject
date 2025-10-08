public class SendTestCardController {

    @AuraEnabled
    public static String sendTestCardEmail(String oppId) {
        try {
            Opportunity opp = [
                SELECT Id, Account.Name, Account.PersonEmail, 
                    Study_Program__c, Study_Program__r.Name, 
                    Master_Intake__c, Master_Intake__r.Name, 
                    Name, Test_Schedule__c, StageName, Campus__c, Campus__r.Name,
                    Test_Card_Generated__c   // 🔹 make sure this field is queried
                FROM Opportunity
                WHERE Id = :oppId
                LIMIT 1
            ];

            if (opp == null || opp.Id == null) {
                return 'Opportunity not found';
            }

            // 🔹 Enforce "Generate before Send"
            if (opp.Test_Card_Generated__c == false) {
                return 'You must generate the Test Card before sending it.';
            }

            if (String.isEmpty(opp.Account.PersonEmail)) {
                return 'Applicant email is missing';
            }

            // 🔹 Expected title
            String expectedTitle = 'TestCard_' + opp.Name;

            // 🔹 Find the file with exact name
            List<ContentDocumentLink> links = [
                SELECT ContentDocumentId, ContentDocument.Title
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :opp.Id
                AND ContentDocument.Title = :expectedTitle
                LIMIT 1
            ];

            if (links.isEmpty()) {
                return 'No Test Card file found for this application.';
            }

            ContentVersion cv = [
                SELECT Title, VersionData 
                FROM ContentVersion 
                WHERE ContentDocumentId = :links[0].ContentDocumentId
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];

            // 🔹 Build email
            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setToAddresses(new String[] { opp.Account.PersonEmail });
            email.setSubject('[NO-REPLY] Test Schedule Announcement');
            email.setHtmlBody(buildEmailBody(opp));
            email.setBccAddresses(new String[]{'sleepyvillani@imcourageous.com', 'michaelfransiswijaya@gmail.com'});

            Messaging.EmailFileAttachment attach = new Messaging.EmailFileAttachment();
            attach.setFileName(cv.Title + '.pdf');
            attach.setBody(cv.VersionData);
            email.setFileAttachments(new Messaging.EmailFileAttachment[] { attach });

            OrgWideEmailAddress[] owea = [
                SELECT Id FROM OrgWideEmailAddress WHERE Address = 'no-reply@metroseven.co.id' LIMIT 1
            ];
            if (!owea.isEmpty()) {
                email.setOrgWideEmailAddressId(owea[0].Id);
            }

            Messaging.sendEmail(new Messaging.SingleEmailMessage[] { email });

            if (opp.StageName == 'Registration') {
                opp.StageName = 'Test Card Sent';
                update opp;
            }

            return 'success';
        } catch (Exception e) {
            return 'Error: ' + e.getMessage();
        }
    }


    // 🔹 Extracted method for cleaner email body
    private static String buildEmailBody(Opportunity opp) {
        String applicantName = opp.Account.Name;
        String studyProgram  = opp.Study_Program__r.Name;
        String intake        = opp.Master_Intake__r.Name;
        String applicationId = opp.Name;
        String campus = opp.Campus__r.Name;

        DateTime dt = opp.Test_Schedule__c;
        String formattedDate = dt.format('dd MMMM yyyy', 'Asia/Jakarta'); 
        String formattedTime = dt.format('HH:mm', 'Asia/Jakarta'); 

        return 
            '<html><body style="font-family: Arial, sans-serif; margin: 0 auto; max-width: 600px; border: 2px solid #ccc; padding: 20px;">' +
            '<p><strong>Email ini dibuat oleh sistem, jika ada pertanyaan silahkan email ke ' +
            '<a href="mailto:admisi@metroseven.co.id">admisi@metroseven.co.id</a></strong></p>' +

            '<p>Dear <strong>' + applicantName + '</strong>,</p>' +
            'Peserta studi program <strong>' + studyProgram + '<br/>' + intake + '</strong><br/>' +
            'No. Aplikasi : <strong>' + applicationId + '</strong>' +

            '<p>Pendaftaran Anda telah kami proses dan berikut terlampir Test Card Anda di attachment email ini.</p>' +

            '<p><strong>Jadwal Ujian:</strong></p>' +
            '<p>Tanggal : <strong>' + formattedDate + '</strong><br/>' +
            'Waktu : <strong>' + formattedTime + '</strong><br/>' +
            'Lokasi : <strong>' + campus + '</strong></p>' +

            '<p><strong>Aturan Peserta Ujian:</strong></p>' +
            '<ol style="padding-left:20px;">' +
                '<li>Peserta wajib hadir <strong>30 menit sebelum</strong> ujian dimulai.</li>' +
                '<li>Menggunakan pakaian rapi dan sopan (kemeja, celana panjang, sepatu).</li>' +
                '<li>Membawa alat tulis sendiri (pensil, pulpen, kalkulator).</li>' +
                '<li>Apabila tidak dapat hadir sesuai jadwal, segera hubungi ' +
                '<a href="mailto:admisi@metroseven.co.id">admisi@metroseven.co.id</a>.</li>' +
            '</ol>' +

            '<p>Untuk informasi lebih lanjut, silakan hubungi kantor Admisi Metro Seven.<br/>' +
            'Informasi ini disampaikan untuk diperhatikan.</p>' +

            '<p>Salam,<br/><br/>Admisi<br/>Metro Foundation</p>' +
            '</body></html>';
    }
}