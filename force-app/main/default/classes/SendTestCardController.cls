public class SendTestCardController {

    @AuraEnabled
    public static String sendTestCardEmail(String oppId) {
        try {
            Opportunity opp = [
                SELECT Id, Account.Name, Account.PersonEmail, 
                    Study_Program__c, Study_Program__r.Name, 
                    Master_Intake__c, Master_Intake__r.Name, 
                    Name, Test_Schedule__c, StageName, Campus__c
                FROM Opportunity
                WHERE Id = :oppId
                LIMIT 1
            ];

            if (opp == null || opp.Id == null) {
                return 'Opportunity not found';
            }

            if (String.isEmpty(opp.Account.PersonEmail)) {
                return 'Applicant email is missing';
            }

            // 🔹 Build email body
            String applicantName = opp.Account.Name;
            String studyProgram  = opp.Study_Program__r.Name;
            String intake        = opp.Master_Intake__r.Name;
            String applicationId = opp.Name;
            String campus = opp.Campus__c;
            
            // Combine into DateTime for formatting
            DateTime dt = opp.Test_Schedule__c;
            // Format date part
            String formattedDate = dt.format('dd MMMM yyyy', 'Asia/Jakarta'); 
            // Format time part (24h or 12h)
            String formattedTime = dt.format('HH:mm', 'Asia/Jakarta'); 

            // String emailBody = 
            //     '<html><body style="font-family: Arial, sans-serif; margin: 0 auto; max-width: 600px; border: 2px solid #ccc; padding: 20px;">' +
            //     'Dear <strong>' + applicantName + '</strong>,<br/>' +
            //     '<strong>' + studyProgram + '</strong> program participant,<br/>' +
            //     '<strong>' + intake + '</strong><br/>' +
            //     'Application ID: <strong>' + applicationId + '</strong><br/><br/>' +
            //     'We have processed your registration, and we are attaching your test card to this email.<br/>' +
            //     'Your test will be held on:<br/>' +
            //     'Date: <strong>' + formattedDate + '</strong><br/>' +
            //     'Time: <strong>' + formattedTime + '</strong><br/><br/>' +
            //     'Test participants must:<br/>' +
            //     '1. Arrive <strong>30 minutes before</strong> the test begins.<br/>' +
            //     '2. Wear neat and appropriate attire (shirt, trousers, shoes).<br/>' +
            //     '3. Bring your own writing materials (pencils, pens, calculators).<br/>' +
            //     '4. If you cannot attend at the scheduled time, please contact admisi@metroseven.co.id.<br/><br/>' +
            //     'For further information, please contact the Metro Seven admissions office.<br/>' +
            //     'This information is provided for your consideration.<br/><br/>' +
            //     'Regards,<br/><br/>' +
            //     'Admissions Office<br/>' +
            //     'Metro Foundation' +
            //     '</body></html>';

            String emailBody = 
                '<html><body style="font-family: Arial, sans-serif; margin: 0 auto; max-width: 600px; border: 2px solid #ccc; padding: 20px;">' +

                // header note
                '<p><strong>Email ini dibuat oleh sistem, jika ada pertanyaan silahkan email ke ' +
                '<a href="mailto:admisi@metroseven.co.id">admisi@metroseven.co.id</a></strong></p>' +

                // applicant info
                '<p>Dear <strong>' + applicantName + '</strong>,</p>' +

                'Peserta studi program <strong>' + studyProgram + '<br/>' + intake + '</strong><br/>' +
                'No. Aplikasi : <strong>' + applicationId + '</strong>' +

                // intro
                '<p>Pendaftaran Anda telah kami proses dan berikut Test Card Anda di attachment email ini.</p>' +

                // schedule
                '<p><strong>Jadwal Ujian:</strong></p>' +
                '<p>' +
                'Tanggal : <strong>' + formattedDate + '</strong><br/>' +
                'Waktu : <strong>' + formattedTime + '</strong>' +
                'Lokasi : <strong>' + campus + '</strong>' +
                '</p>' +

                // rules
                '<p><strong>Aturan Peserta Ujian:</strong></p>' +
                '<ol style="padding-left:20px;">' +
                    '<li>Peserta wajib hadir <strong>30 menit sebelum</strong> ujian dimulai.</li>' +
                    '<li>Menggunakan pakaian rapi dan sopan (kemeja, celana panjang, sepatu).</li>' +
                    '<li>Membawa alat tulis sendiri (pensil, pulpen, kalkulator).</li>' +
                    '<li>Apabila tidak dapat hadir sesuai jadwal, segera hubungi ' +
                    '<a href="mailto:admisi@metroseven.co.id">admisi@metroseven.co.id</a>.</li>' +
                '</ol>' +

                // closing
                '<p>Untuk informasi lebih lanjut, silakan hubungi kantor Admisi Metro Seven.<br/>' +
                'Informasi ini disampaikan untuk diperhatikan.</p>' +

                '<p>Salam,<br/><br/>' +
                'Admisi<br/>' +
                'Metro Foundation</p>' +

                '</body></html>';


            // 🔹 Get latest attached ContentDocument
            List<ContentDocumentLink> links = [
                SELECT ContentDocumentId
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :opp.Id
                ORDER BY ContentDocument.CreatedDate DESC
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
            email.setHtmlBody(emailBody);
            email.setBccAddresses(new String[]{'sleepyvillani@imcourageous.com', 'michaelfransiswijaya@gmail.com'});

            Messaging.EmailFileAttachment attach = new Messaging.EmailFileAttachment();
            attach.setFileName(cv.Title + '.pdf');
            attach.setBody(cv.VersionData);
            email.setFileAttachments(new Messaging.EmailFileAttachment[] { attach });

            // Optionally use OrgWideEmailAddress
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
}
