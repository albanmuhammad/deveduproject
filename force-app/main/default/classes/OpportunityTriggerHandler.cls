public with sharing class OpportunityTriggerHandler extends TriggerHandler { 

    protected override void afterInsert() {
        // Make a copy
        List<Opportunity> opps = new List<Opportunity>();
        for (Opportunity o : (List<Opportunity>) Trigger.new) {
            opps.add(o);
        }

        // Test Info
        CreateTestInfoController.handleTestInfoCreation(opps, null);

        // Payment Info
        PaymentInfoFromOpporyunityController.createPaymentInfo(opps);

        // Active Flag handling (new opps should be active)
        OpportunityActiveFlagController.handleAfterInsert(opps);

        // Create quota log
        StudyProgramQuotaLogController.createQuotaLogs(opps, null);

        // Generate Student Number for Closed Won opps
        StudentNumberController.assignForClosedWon(opps, null);
    }

    protected override void afterUpdate() {
        // Make safe copies
        List<Opportunity> oppsNew = new List<Opportunity>();
        for (Opportunity o : (List<Opportunity>) Trigger.new) {
            oppsNew.add(o);
        }

        Map<Id, Opportunity> oppsOldMap = new Map<Id, Opportunity>();
        for (Opportunity o : (List<Opportunity>) Trigger.old) {
            oppsOldMap.put(o.Id, o);
        }

        // Test Info
        CreateTestInfoController.handleTestInfoCreation(oppsNew, oppsOldMap);

        // jalankan hanya saat berubah dari false -> true
        List<Opportunity> oppsForPayment = new List<Opportunity>();
        for (Integer i = 0; i < oppsNew.size(); i++) {
            Opportunity newOpp = oppsNew[i];
            Opportunity oldOpp = (Trigger.old != null ? (Opportunity) Trigger.old[i] : null);

            if (newOpp.Is_Booking_Fee_Paid__c == true &&
                (oldOpp == null || oldOpp.Is_Booking_Fee_Paid__c != true)) {
                oppsForPayment.add(newOpp);
            }
        }
        if (!oppsForPayment.isEmpty()) {
            PaymentInfoFromOpporyunityController.createPaymentInfo(oppsForPayment);
        }

        // Batch study program
        OpportunityBatchStudyProgramController.handleBatchStudyProgram(oppsNew, oppsOldMap);

        // Active Flag handling (updates)
        OpportunityActiveFlagController.handleAfterUpdate(oppsNew, oppsOldMap);

        // Amount calculation when Stage = 'Test Passed'
        OpportunityAmountController.handleAmountCalculation(oppsNew, oppsOldMap);

        // Quota Log update on Closed Lost
        StudyProgramQuotaLogController.createQuotaLogs(oppsNew, oppsOldMap);

        // Generate Student Number for Closed Won opps
        StudentNumberController.assignForClosedWon(oppsNew, oppsOldMap);
    }
}