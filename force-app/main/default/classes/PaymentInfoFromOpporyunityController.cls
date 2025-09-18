public with sharing class PaymentInfoFromOpporyunityController {
    public static void createPaymentInfo(List<Opportunity> opps) {
        List<Payment_Information__c> payments = new List<Payment_Information__c>();

        for (Opportunity opp : opps) {
            if (opp.Is_Booking_Fee_Paid__c == true) {
                Payment_Information__c pi = new Payment_Information__c();
                pi.Allocation__c = 'Registration Fee';
                pi.Payment_For__c = 'Full Payment';
                pi.Payment_Status__c = 'Paid';
                pi.Amount__c = 100000; 
                pi.Application_Progress__c = opp.Id; 
                payments.add(pi);
            }
        }

        if (!payments.isEmpty()) {
            insert payments;
        }
    }
}