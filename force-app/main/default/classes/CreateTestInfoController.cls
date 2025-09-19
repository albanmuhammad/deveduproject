public with sharing class CreateTestInfoController {
    public static void handleTestInfoCreation(List<Opportunity> newList, Map<Id, Opportunity> oldMap) {
        Set<Id> batchIds = new Set<Id>();
        List<Opportunity> oppsToProcess = new List<Opportunity>();

        for (Opportunity newOppty : newList) {
            Opportunity oldOppty = (oldMap != null ? oldMap.get(newOppty.Id) : null);

            Boolean shouldProcess = false;

            // Insert case: batch already filled
            if (oldMap == null && newOppty.Master_Batch__c != null && newOppty.AccountId != null) {
                shouldProcess = true;
            }

            // Update case: batch changed from null → not null
            if (oldMap != null 
                && oldOppty.Master_Batch__c == null 
                && newOppty.Master_Batch__c != null 
                && newOppty.AccountId != null) {
                shouldProcess = true;
            }

            if (shouldProcess) {
                oppsToProcess.add(newOppty);
                batchIds.add(newOppty.Master_Batch__c);
            }
        }

        if (oppsToProcess.isEmpty()) return;

        // Query batches
        Map<Id, Master_Batches__c> batchMap = new Map<Id, Master_Batches__c>(
            [SELECT Id, Test_Schedule__c FROM Master_Batches__c WHERE Id IN :batchIds]
        );

        // Prevent duplicates
        Set<Id> oppIds = new Map<Id, Opportunity>(oppsToProcess).keySet();
        Map<Id, Test_Information__c> existingTestInfo = new Map<Id, Test_Information__c>(
            [SELECT Id, Application_Progress__c 
             FROM Test_Information__c 
             WHERE Application_Progress__c IN :oppIds]
        );

        // Build inserts
        List<Test_Information__c> testInfoToInsert = new List<Test_Information__c>();
        for (Opportunity oppty : oppsToProcess) {
            if (!existingTestInfo.containsKey(oppty.Id)) {
                Master_Batches__c batch = batchMap.get(oppty.Master_Batch__c);

                testInfoToInsert.add(new Test_Information__c(
                    Application_Progress__c = oppty.Id,
                    Applicant__c = oppty.AccountId,
                    Master_Batch__c = oppty.Master_Batch__c,
                    Name = 'Test-' + oppty.AccountId,
                    Test_Schedule__c = (batch != null ? batch.Test_Schedule__c : null)
                ));
            }
        }

        if (!testInfoToInsert.isEmpty()) {
            insert testInfoToInsert;
        }
    }
}