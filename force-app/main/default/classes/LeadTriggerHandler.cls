public with sharing class LeadTriggerHandler extends TriggerHandler {
    protected override void afterUpdate() {
        List<Database.LeadConvert> leadConverts = new List<Database.LeadConvert>();

        for (Lead l : (List<Lead>) Trigger.new) {
            Lead oldLead = (Lead) Trigger.oldMap.get(l.Id);

            // Only act when checkbox is flipped from false → true
            if (l.Is_Convert__c == true && oldLead.Is_Convert__c == false) {
                System.debug('Checkbox flipped!');
                Database.LeadConvert lc = new Database.LeadConvert();
                lc.setLeadId(l.Id);

                // Set Converted Status (must match one of your Converted statuses in Setup → Lead Statuses)
                lc.setConvertedStatus('Converted');

                // Create Person Account (make sure Person Accounts are enabled in your org)
                lc.setDoNotCreateOpportunity(false); // we want Opportunity created
                lc.setOpportunityName(l.FirstName + ' ' + l.LastName + '/');

                leadConverts.add(lc);
            }
        }

        if (!leadConverts.isEmpty()) {
            List<Database.LeadConvertResult> results = Database.convertLead(leadConverts, false);

            for (Database.LeadConvertResult res : results) {
                if (!res.isSuccess()) {
                    for (Database.Error err : res.getErrors()) {
                        System.debug('Lead conversion failed: ' + err.getMessage());
                    }
                }
            }
        }
    }
}