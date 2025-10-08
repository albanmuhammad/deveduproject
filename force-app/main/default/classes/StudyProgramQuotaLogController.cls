public with sharing class StudyProgramQuotaLogController {

    public static void createQuotaLogs(List<Opportunity> newList, Map<Id, Opportunity> oldMap) {
        List<Study_Program_Quota_Log__c> logs = new List<Study_Program_Quota_Log__c>();

        // Collect all Batch_Study_Program__c Ids
        Set<Id> bspIds = new Set<Id>();
        for (Opportunity opp : newList) {
            if (opp.Batch_Study_Program__c != null) {
                bspIds.add(opp.Batch_Study_Program__c);
            }
        }

        // Query Study Program Intake
        Map<Id, Batch_Study_Program__c> bspMap = new Map<Id, Batch_Study_Program__c>(
            [SELECT Id, Study_Program_Intake__c
            FROM Batch_Study_Program__c
            WHERE Id IN :bspIds]
        );

        for (Opportunity opp : newList) {
            Opportunity oldOpp = (oldMap != null && oldMap.containsKey(opp.Id)) ? oldMap.get(opp.Id) : null;

            // Case 1&2: Batch_Study_Program__c newly filled
            if (opp.Batch_Study_Program__c != null &&
                (oldOpp == null || oldOpp.Batch_Study_Program__c == null)) {

                logs.add(new Study_Program_Quota_Log__c(
                    Application_Progress__c = opp.Id,
                    Study_Program_Intake__c = bspMap.get(opp.Batch_Study_Program__c).Study_Program_Intake__c,
                    Quota__c = 1
                ));
            }

            // Case 3: Stage moved to Closed Lost
            if (oldOpp != null && opp.StageName == 'Closed Lost' && oldOpp.StageName != 'Closed Lost') {
                if (opp.Batch_Study_Program__c != null) {
                    logs.add(new Study_Program_Quota_Log__c(
                        Application_Progress__c = opp.Id,
                        Study_Program_Intake__c = bspMap.get(opp.Batch_Study_Program__c).Study_Program_Intake__c,
                        Quota__c = -1
                    ));
                }
            }
        }

        if (!logs.isEmpty()) {
            insert logs;
        }
    }

}