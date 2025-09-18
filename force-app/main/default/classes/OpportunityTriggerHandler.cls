public with sharing class OpportunityTriggerHandler extends TriggerHandler {

    protected override void afterInsert() {
        // cast setiap SObject ke Opportunity sebelum dipakai/dioper
        List<Opportunity> opps = new List<Opportunity>();
        for (SObject sob : Trigger.new) {
            opps.add((Opportunity)sob);
        }
        PaymentInfoFromOpporyunityController.createPaymentInfo(opps);
    }

    protected override void afterUpdate() {
        // jalankan hanya saat berubah dari false -> true
        List<Opportunity> opps = new List<Opportunity>();

        for (Integer i = 0; i < Trigger.new.size(); i++) {
            Opportunity newOpp = (Opportunity)Trigger.new[i];
            Opportunity oldOpp = (Opportunity)Trigger.old[i];

            if (newOpp.Is_Booking_Fee_Paid__c == true &&
                (oldOpp == null || oldOpp.Is_Booking_Fee_Paid__c != true)) {
                opps.add(newOpp);
            }
        }

        if (!opps.isEmpty()) {
            PaymentInfoFromOpporyunityController.createPaymentInfo(opps);
        }
    }
}
