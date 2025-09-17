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
            SELECT Id, Amount, Account.Phone
            FROM Opportunity
            WHERE Id = :oppId
        ];

        // Ambil VA Prefix dari Payment Channel
        Payment_Channel__c ch = [
            SELECT Id, VA_Prefix__c
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
        String phone = (opp.Account == null) ? null : opp.Account.Phone;
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
            toInsert.add(pi);
        }
        insert toInsert;
    }
}
