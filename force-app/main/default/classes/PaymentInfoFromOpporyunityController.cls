public with sharing class PaymentInfoFromOpporyunityController {
    public static void createPaymentInfo(List<Opportunity> opps) {
        // Collect Study Program Ids from opps
        Set<Id> studyProgramIds = new Set<Id>();
        for (Opportunity opp : opps) {
            if (opp.Study_Program__c != null) {
                studyProgramIds.add(opp.Study_Program__c);
            }
        }

        // Query Study Programs
        Map<Id, Study_Program__c> studyProgramMap = new Map<Id, Study_Program__c>(
            [SELECT Id, Booking_Form_Price__c
             FROM Study_Program__c 
             WHERE Id IN :studyProgramIds]
        );

        List<Payment_Information__c> payments = new List<Payment_Information__c>();

        for (Opportunity opp : opps) {
            if (opp.Is_Booking_Fee_Paid__c == true && opp.Study_Program__c != null) {
                Study_Program__c sp = studyProgramMap.get(opp.Study_Program__c);

                Payment_Information__c pi = new Payment_Information__c();
                pi.Allocation__c = 'Registration Fee';
                pi.Payment_For__c = 'Full Payment';
                pi.Payment_Status__c = 'Paid';
                pi.Amount__c = sp != null ? sp.Booking_Form_Price__c : 0; // take fee from study program
                pi.Application_Progress__c = opp.Id; 
                payments.add(pi);
            }
        }

        if (!payments.isEmpty()) {
            insert payments;
        }
    }
}