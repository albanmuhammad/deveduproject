public with sharing class OpportunityTriggerHandler extends TriggerHandler {

    protected override void afterInsert() {
    Set<Id> batchIds = new Set<Id>();
    List<Opportunity> opps = new List<Opportunity>();
    for (Opportunity oppty : (List<Opportunity>) Trigger.new) {
        opps.add(oppty);
        if (oppty.Master_Batch__c != null) {
            batchIds.add(oppty.Master_Batch__c);
        }
    }

    Map<Id, Master_Batches__c> batchMap = new Map<Id, Master_Batches__c>(
        [SELECT Id, Test_Schedule__c FROM Master_Batches__c WHERE Id IN :batchIds]
    );

    List<Test_Information__c> testInfoToInsert = new List<Test_Information__c>();

    for (Opportunity oppty : (List<Opportunity>) Trigger.new) {
        if (oppty.AccountId != null && oppty.Master_Batch__c != null) {
            Master_Batches__c batch = batchMap.get(oppty.Master_Batch__c);
            Test_Information__c testInfo = new Test_Information__c(
                Application_Progress__c = oppty.Id,
                Applicant__c = oppty.AccountId,
                Master_Batch__c = oppty.Master_Batch__c,
                Name = 'Test-' + oppty.AccountId,
                Test_Schedule__c = (batch != null ? batch.Test_Schedule__c : null)
            );
            testInfoToInsert.add(testInfo);
        }
    }

    if (!testInfoToInsert.isEmpty()) {
        insert testInfoToInsert;
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
