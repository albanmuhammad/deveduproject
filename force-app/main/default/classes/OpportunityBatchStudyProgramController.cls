public with sharing class OpportunityBatchStudyProgramController {
    public static void handleBatchStudyProgram(List<Opportunity> newList, Map<Id, Opportunity> oldMap) {
        List<Opportunity> toUpdate = new List<Opportunity>();
        for (Opportunity newOpp : newList) {
            Opportunity oldOpp = (oldMap != null) ? oldMap.get(newOpp.Id) : null;

            // Run if any of these fields change:
            Boolean studyProgramChanged = (oldOpp == null || newOpp.Study_Program__c != oldOpp.Study_Program__c);
            Boolean intakeChanged       = (oldOpp == null || newOpp.Master_Intake__c != oldOpp.Master_Intake__c);
            Boolean batchChanged        = (oldOpp == null || newOpp.Master_Batch__c != oldOpp.Master_Batch__c);

            if (newOpp.Study_Program__c != null 
                && newOpp.Master_Intake__c != null 
                && newOpp.Master_Batch__c != null 
                && (studyProgramChanged || intakeChanged || batchChanged)) 
            {
                toUpdate.add(newOpp);
            }
        }

        if (toUpdate.isEmpty()) return;

        // Collect Ids
        Set<Id> studyProgramIds = new Set<Id>();
        Set<Id> intakeIds       = new Set<Id>();
        Set<Id> batchIds        = new Set<Id>();
        Set<Id> accountIds      = new Set<Id>();

        for (Opportunity opp : toUpdate) {
            if (opp.Study_Program__c != null) studyProgramIds.add(opp.Study_Program__c);
            if (opp.Master_Intake__c != null) intakeIds.add(opp.Master_Intake__c);
            if (opp.Master_Batch__c != null) batchIds.add(opp.Master_Batch__c);
            if (opp.AccountId != null) accountIds.add(opp.AccountId);
        }

        // Query junctions
        Map<String, Batch_Study_Program__c> junctionMap = new Map<String, Batch_Study_Program__c>();
        for (Batch_Study_Program__c bsp : [
            SELECT Id, Name, Study_Program__c, Study_Program_Intake__c, Study_Program_Intake__r.Master_Intake__c, Master_Batch__c
            FROM Batch_Study_Program__c
            WHERE Study_Program__c IN :studyProgramIds
              AND Study_Program_Intake__r.Master_Intake__c IN :intakeIds
              AND Master_Batch__c IN :batchIds
        ]) {
            String key = bsp.Study_Program__c + '-' + bsp.Study_Program_Intake__r.Master_Intake__c + '-' + bsp.Master_Batch__c;
            junctionMap.put(key, bsp);
        }

        // Query Accounts for First/LastName  (NO query in loop)
        Map<Id, Account> acctMap = new Map<Id, Account>();
        if (!accountIds.isEmpty()) {
            List<Account> accList = [
                SELECT Id, FirstName, LastName
                FROM Account
                WHERE Id IN :accountIds
            ];
            for (Account acc : accList) {
                acctMap.put(acc.Id, acc);
            }
        }

        // Query Batches for Test_Schedule__c  (NO query in loop)
        Map<Id, Master_Batches__c> batchMap = new Map<Id, Master_Batches__c>();
        if (!batchIds.isEmpty()) {
            List<Master_Batches__c> batchList = [
                SELECT Id, Test_Schedule__c
                FROM Master_Batches__c
                WHERE Id IN :batchIds
            ];
            for (Master_Batches__c b : batchList) {
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

                    // Build Opportunity.Name
                    if (opp.AccountId != null && acctMap.containsKey(opp.AccountId)) {
                        Account acc = acctMap.get(opp.AccountId);
                        String firstName = acc.FirstName != null ? acc.FirstName : '';
                        String lastName  = acc.LastName != null ? acc.LastName : '';
                        String batchName = bsp.Name != null ? bsp.Name : '';
                        upd.Name = (firstName + ' ' + lastName + '/REG/' + batchName).trim();
                    }

                    // Copy Test_Schedule__c
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
}