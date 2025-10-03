public with sharing class PaymentInformationController {
    public class PaymentItemDTO {
        @AuraEnabled public Integer num { get; set; }
        @AuraEnabled public Decimal amount { get; set; }
        @AuraEnabled public Date dueDate { get; set; }
    }

    @AuraEnabled
    public static void savePayments(Id oppId, List<PaymentItemDTO> items, Id paymentChannelId, String allocation, String paymentStatus) {
        if (oppId == null) throw new AuraHandledException('Opp Id kosong');
        if (items == null || items.isEmpty()) throw new AuraHandledException('Tidak ada data installment');
        if (paymentChannelId == null) throw new AuraHandledException('Pilih Payment Channel terlebih dahulu.');

        // Ambil Amount + Phone dari Account
        Opportunity opp = [
            SELECT Id, Amount, Account.PersonMobilePhone
            FROM Opportunity
            WHERE Id = :oppId
        ];

        // Ambil VA Prefix dari Payment Channel
        Payment_Channel__c ch = [
            SELECT Id, VA_Prefix__c, Payment_Channel_Bank__c, Name 
            FROM Payment_Channel__c
            WHERE Id = :paymentChannelId
            LIMIT 1
        ];

        // Validasi total
        Decimal sumAmount = 0;
        for (PaymentItemDTO it : items) {
            if (it.amount == null || it.amount <= 0) throw new AuraHandledException('Jumlah installment harus > 0');
            if (it.dueDate == null) throw new AuraHandledException('Due date wajib diisi');
            sumAmount += it.amount;
        }
        if (sumAmount != (opp.Amount == null ? 0 : opp.Amount)) {
            throw new AuraHandledException('Total installment harus sama dengan Opportunity Amount');
        }

        // Build VA: prefix + digits-only phone
        String phone = (opp.Account == null) ? null : opp.Account.PersonMobilePhone;
        if (String.isBlank(phone)) {
            throw new AuraHandledException('Nomor telepon pada Account kosong. Isi Phone di Account terlebih dahulu.');
        }
        String digitsOnly = phone.replaceAll('[^0-9]', '');
        if (String.isBlank(digitsOnly)) {
            throw new AuraHandledException('Nomor telepon pada Account tidak mengandung angka yang valid.');
        }
        String prefix = (ch.VA_Prefix__c == null) ? '' : ch.VA_Prefix__c.trim();
        String virtualAcc = prefix + digitsOnly;

        final String OPP_LOOKUP_FIELD = 'Application_Progress__c';

        List<Payment_Information__c> toInsert = new List<Payment_Information__c>();
        for (PaymentItemDTO it : items) {
            Payment_Information__c pi = new Payment_Information__c();
            pi.put(OPP_LOOKUP_FIELD, oppId);
            pi.Amount__c = it.amount;
            pi.Payment_Status__c = paymentStatus;
            pi.Allocation__c = allocation;
            pi.Due_Date__c = it.dueDate;
            pi.Payment_For__c = (items.size() == 1) ? 'Full Payment' : ('Installment ' + it.num);
            pi.Payment_Channel__c = paymentChannelId;         // ⟵ set channel
            pi.Virtual_Account_No__c = virtualAcc;            // ⟵ set VA No
            pi.Bank__c = ch.Payment_Channel_Bank__c;              // ← tambahkan
            toInsert.add(pi);
        }
        insert toInsert;
        // emailFormPayment(oppId);
    }

    @AuraEnabled
    public static void advanceOppStage(Id oppId) {
        if (oppId == null) throw new AuraHandledException('Opportunity Id kosong');
        
        Opportunity opp = [
            SELECT Id, StageName
            FROM Opportunity
            WHERE Id = :oppId
            LIMIT 1
        ];
        
        if (opp.StageName == 'Test Passed') {
            opp.StageName = 'Payment';
            update opp;
        }
    }

     // ====== DIPAKAI VISUALFORCE (controller instance) ======
    public Id oppId { get; set; }
    public Opportunity opp { get; private set; }
    public List<Payment_Information__c> payments { get; private set; }

    public Decimal totalSPP { get; private set; }
    public Decimal sppTerbayar { get; private set; }
    public Decimal getSisaSPP() { return (totalSPP - sppTerbayar); }

    public String registrationNo { get; private set; }
    public String getAccName() { return (opp != null && opp.Account != null) ? opp.Account.Name : ''; }
    public String getProgramLabel() {
        String study = (opp.Study_Program__r == null) ? '' : opp.Study_Program__r.Name;
        String intake = (opp.Master_Intake__r == null) ? '' : opp.Master_Intake__r.Name;
        return (study + ' ' + intake).trim();
    }

    // Konstruktor VF – dipanggil saat VF page dirender
    public PaymentInformationController() {
        // Hanya jalan saat konteks Visualforce
        if (ApexPages.currentPage() == null) return;
        String p = ApexPages.currentPage().getParameters().get('oppId');
        if (String.isBlank(p)) return;
        oppId = p;
        initForVF();
    }

    private void initForVF() {
        opp = [
            SELECT Id, Name, Amount,
               AccountId, Account.Name, Account.PersonEmail,
               Study_Program__r.Name,
               Master_Intake__r.Name
            FROM Opportunity
            WHERE Id = :oppId
            LIMIT 1
        ];

        payments = [
            SELECT Id, Amount__c, Due_Date__c, Payment_For__c,
                   Name, Virtual_Account_No__c,
                   Bank__c, Bank_Name__c, Payment_Channel__c,
                   Application_Progress__c, Allocation__c
            FROM Payment_Information__c
            WHERE Application_Progress__c = :oppId AND Allocation__c =: 'Tuition Fee'
            ORDER BY Due_Date__c ASC, CreatedDate ASC
        ];

        totalSPP    = (opp.Amount == null ? 0 : opp.Amount);
        sppTerbayar = 0; // kalau ada sumber "sudah bayar", set di sini

        registrationNo = payments.isEmpty()
            ? ''
            : payments[0].Name;
    }

    // ====== Helper: render PDF & kirim email ======
    @AuraEnabled
    public static void emailFormPayment(Id oppId) {
        // 1) PASTIKAN nama page sesuai API Name di org-mu
        PageReference pr = Page.FormPayment;
        pr.getParameters().put('oppId', String.valueOf(oppId));

        // === Test-aware PDF generation ===
        Blob pdfBlob;
        if (Test.isRunningTest()) {
            // In tests, getContentAsPDF() is blocked → use a stub blob
            pdfBlob = Blob.valueOf('stub-pdf');
        } else {
            try {
                pdfBlob = pr.getContentAsPDF();
            } catch (Exception ex) {
                // Fallback diagnostik: coba render halaman minimal (Lite)
                PageReference prLite = Page.FormPayment;
                prLite.getParameters().put('oppId', String.valueOf(oppId));
                Blob lite = prLite.getContentAsPDF();
                throw new AuraHandledException('Gagal render PDF utama. PDF Lite sukses → cek markup/tabel/CSS di VF page utama. Detail: ' + ex.getMessage());
            }
        }

        // Query untuk subject & penerima (termasuk Study Program + Master Intake)
        Opportunity opp = [
            SELECT Id,
                Account.Name, Account.PersonEmail,
                Study_Program__r.Name,
                Master_Intake__r.Name
            FROM Opportunity
            WHERE Id = :oppId
            LIMIT 1
        ];
        if (opp.Account == null || String.isBlank(opp.Account.PersonEmail)) {
            throw new AuraHandledException('Email pada Account kosong.');
        }

        String study  = (opp.Study_Program__r == null) ? '' : opp.Study_Program__r.Name;
        String intake = (opp.Master_Intake__r == null) ? '' : opp.Master_Intake__r.Name;
        String subject = ('Pengumuman & Form B – ' +
                        (String.isBlank(study) ? '' : study + ' ') +
                        (String.isBlank(intake) ? '' : intake)).trim();

        Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
        msg.setToAddresses(new String[]{ opp.Account.PersonEmail });
        msg.setCcAddresses(new List<String>{ 'admisi@metroseven.ac.id', 'finance@metroseven.ac.id' });
        msg.setSubject(subject);
        msg.setHtmlBody(
            '<p>Email ini dibuat oleh sistem, jika ada pertanyaan silakan email ke '+
            '<a href="mailto:admisi@metroseven.ac.id">admisi@metroseven.ac.id</a>.</p>'+
            '<p>Kepada <b>' + opp.Account.Name + '</b>,</p>'+
            '<p>Pendaftaran Anda telah kami proses dan <b>Form B / Offer Letter</b> terlampir.</p>'+
            '<p><b>Aturan Pembayaran SPP (ringkas):</b></p>'+
            '<ol>'+
            '<li>SPP dibayarkan sekali untuk masa studi dan tidak termasuk BPP-SKS.</li>'+
            '<li>Lewat jatuh tempo dianggap mengundurkan diri dan kursi tidak kami jamin.</li>'+
            '<li>Pembayaran yang sudah dilakukan tidak dapat dikembalikan/dialihkan.</li>'+
            '<li>Form sah tanpa tanda tangan pejabat terkait.</li>'+
            '</ol>'+
            '<p>Info: Telp (021) 5695-8723 / WhatsApp 0811-7579-727.</p>'+
            '<p>Salam,<br/>Admisi Universitas metroseven</p>'
        );

        Messaging.EmailFileAttachment att = new Messaging.EmailFileAttachment();
        att.setFileName('Form Pembayaran - ' + opp.Account.Name + '.pdf');
        att.setContentType('application/pdf');
        att.setBody(pdfBlob);
        msg.setFileAttachments(new Messaging.EmailFileAttachment[]{ att });

        Messaging.SendEmailResult[] r = Messaging.sendEmail(new Messaging.SingleEmailMessage[]{ msg }, false);
        if (r == null || r.isEmpty() || !r[0].isSuccess()) {
            String err = (r != null && !r.isEmpty() && r[0].getErrors() != null && r[0].getErrors().size() > 0)
                ? r[0].getErrors()[0].getMessage()
                : 'Unknown email send error';
            throw new AuraHandledException('Gagal mengirim email: ' + err);
        }
    }
}