public with sharing class OpportunityTriggerHandler extends TriggerHandler { 

    protected override void afterInsert() {
        // Test Info
        CreateTestInfoController.handleTestInfoCreation((List<Opportunity>) Trigger.new, null);

        // Payment Info
        List<Opportunity> opps = (List<Opportunity>) Trigger.new;
        PaymentInfoFromOpporyunityController.createPaymentInfo(opps);

        // Active Flag handling (new opps should be active)
        OpportunityActiveFlagController.handleAfterInsert(opps);
    }

    protected override void afterUpdate() {
        // Test Info
        CreateTestInfoController.handleTestInfoCreation((List<Opportunity>) Trigger.new, (Map<Id, Opportunity>) Trigger.oldMap);

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

        /* -------------------- NEW LOGIC: Batch_Study_Program__c + Name -------------------- */
        // (your existing name & junction logic stays unchanged)
        List<Opportunity> toUpdate = new List<Opportunity>();
        for (Opportunity newOpp : (List<Opportunity>) Trigger.new) {
            Opportunity oldOpp = ((Map<Id, Opportunity>) Trigger.oldMap).get(newOpp.Id);

            // Run only when Batch__c becomes newly populated
            if (newOpp.Master_Batch__c != null && (oldOpp == null || oldOpp.Master_Batch__c == null)) {
                toUpdate.add(newOpp);
            }
        }

        if (!toUpdate.isEmpty()) {
            Set<Id> studyProgramIds = new Set<Id>();
            Set<Id> intakeIds = new Set<Id>();
            Set<Id> batchIds = new Set<Id>();
            Set<Id> accountIds = new Set<Id>();

            for (Opportunity opp : toUpdate) {
                if (opp.Study_Program__c != null) studyProgramIds.add(opp.Study_Program__c);
                if (opp.Master_Intake__c != null) intakeIds.add(opp.Master_Intake__c);
                if (opp.Master_Batch__c != null) batchIds.add(opp.Master_Batch__c);
                if (opp.AccountId != null) accountIds.add(opp.AccountId);
            }

            // Query junctions
            Map<String, Batch_Study_Program__c> junctionMap = new Map<String, Batch_Study_Program__c>();
            for (Batch_Study_Program__c bsp : [
                SELECT Id, Name, Study_Program__c, Study_Program_Intake__c, Study_Program_Intake__r.Master_Intake__c ,Master_Batch__c
                FROM Batch_Study_Program__c
                WHERE Study_Program__c IN :studyProgramIds
                AND Study_Program_Intake__r.Master_Intake__c IN :intakeIds
                AND Master_Batch__c IN :batchIds
            ]) {
                String key = bsp.Study_Program__c + '-' + bsp.Study_Program_Intake__r.Master_Intake__c + '-' + bsp.Master_Batch__c;
                junctionMap.put(key, bsp);
            }

            // Query Accounts for First/LastName
            Map<Id, Account> acctMap = new Map<Id, Account>();
            if (!accountIds.isEmpty()) {
                for (Account acc : [
                    SELECT Id, FirstName, LastName 
                    FROM Account 
                    WHERE Id IN :accountIds
                ]) {
                    acctMap.put(acc.Id, acc);
                }
            }

            // Query Batches for Test_Schedule__c
            Map<Id, Master_Batches__c> batchMap = new Map<Id, Master_Batches__c>();
            if (!batchIds.isEmpty()) {
                for (Master_Batches__c b : [
                    SELECT Id, Test_Schedule__c 
                    FROM Master_Batches__c 
                    WHERE Id IN :batchIds
                ]) {
                    batchMap.put(b.Id, b);
                }
            }

            List<Opportunity> updates = new List<Opportunity>();
            for (Opportunity opp : toUpdate) {
                if (opp.Study_Program__c != null && opp.Master_Intake__c != null && opp.Master_Batch__c != null) {
                    String key = opp.Study_Program__c + '-' + opp.Master_Intake__c + '-' + opp.Master_Batch__c;
                    if (junctionMap.containsKey(key)) {
                        Batch_Study_Program__c bsp = junctionMap.get(key);
                        Opportunity upd = new Opportunity(Id = opp.Id);
                        upd.Batch_Study_Program__c = bsp.Id;

                        // Build Opportunity.Name = FirstName LastName/REG/BatchStudyProgramName
                        if (opp.AccountId != null && acctMap.containsKey(opp.AccountId)) {
                            Account acc = acctMap.get(opp.AccountId);
                            String firstName = acc.FirstName != null ? acc.FirstName : '';
                            String lastName  = acc.LastName != null ? acc.LastName : '';
                            String batchName = bsp.Name != null ? bsp.Name : '';
                            upd.Name = (firstName + ' ' + lastName + '/REG/' + batchName).trim();
                        }

                        // Copy Test_Schedule__c from Batch__c
                        if (batchMap.containsKey(opp.Master_Batch__c)) {
                            upd.Test_Schedule__c = batchMap.get(opp.Master_Batch__c).Test_Schedule__c;
                        }

                        updates.add(upd);
                    }
                }
            }

            if (!updates.isEmpty()) {
                update updates;
            }
        }

        // Active Flag handling (updates)
        OpportunityActiveFlagController.handleAfterUpdate((List<Opportunity>) Trigger.new, (Map<Id, Opportunity>) Trigger.oldMap);

        // Amount calculation when Stage = 'Test Passed'
        OpportunityAmountController.handleAmountCalculation(
            (List<Opportunity>) Trigger.new,
            (Map<Id, Opportunity>) Trigger.oldMap
        );
    }
}
