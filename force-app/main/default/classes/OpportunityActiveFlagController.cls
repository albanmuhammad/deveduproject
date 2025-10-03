public with sharing class OpportunityActiveFlagController {

    // Called on insert: new opps should default to active, others off
    public static void handleAfterInsert(List<Opportunity> newOpps) {
        if (newOpps.isEmpty()) return;
        updateActiveFlag(newOpps, null, true);
    }

    // Called on update: if IsActive flipped to true, deactivate siblings
    public static void handleAfterUpdate(List<Opportunity> newOpps, Map<Id, Opportunity> oldMap) {
        if (newOpps.isEmpty()) return;
        updateActiveFlag(newOpps, oldMap, false);
    }

    // Core logic
    private static void updateActiveFlag(List<Opportunity> newOpps, Map<Id, Opportunity> oldMap, Boolean isInsert) {
        Set<Id> accountIds = new Set<Id>();
        List<Opportunity> activatedOpps = new List<Opportunity>();
        List<Opportunity> oppsToUpdate = new List<Opportunity>();

        for (Opportunity opp : newOpps) {
            if (opp.AccountId == null) continue;
            accountIds.add(opp.AccountId);

            if (isInsert) {
                // new opps always active → put into update list
                if (opp.Is_Active__c != true) {
                    Opportunity upd = new Opportunity(Id = opp.Id);
                    upd.Is_Active__c = true;
                    oppsToUpdate.add(upd);
                }
                activatedOpps.add(opp);
            } else {
                // only run when IsActive flips false -> true
                Boolean oldValue = oldMap != null && oldMap.containsKey(opp.Id) ? oldMap.get(opp.Id).Is_Active__c : false;
                if (opp.Is_Active__c == true && oldValue != true) {
                    activatedOpps.add(opp);
                }
            }
        }

        // Deactivate siblings
        for (Opportunity activated : activatedOpps) {
            List<Opportunity> siblings = [
                SELECT Id, Is_Active__c
                FROM Opportunity
                WHERE AccountId = :activated.AccountId
                AND Id != :activated.Id
                AND Is_Active__c = true
            ];
            for (Opportunity sib : siblings) {
                oppsToUpdate.add(new Opportunity(Id = sib.Id, Is_Active__c = false));
            }
        }

        if (!oppsToUpdate.isEmpty()) {
            update oppsToUpdate;
        }
    }
}