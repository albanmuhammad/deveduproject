@IsTest
private class LeadTriggerHandlerTest {
    /**
     * Utility: get any NON-converted lead status label to use on insert.
     */
    private static String getOpenLeadStatus() {
        LeadStatus s = [
            SELECT MasterLabel, IsConverted
            FROM LeadStatus
            WHERE IsConverted = false
            LIMIT 1
        ];
        return s.MasterLabel;
    }

    @IsTest
    static void testConversion_whenCheckboxFlips_true() {
        // Arrange
        String openStatus = getOpenLeadStatus();

        Lead toConvert = new Lead(
            FirstName   = 'Ava',
            LastName    = 'Test',
            Company     = 'Acme Co', // required if Person Accounts are not enabled
            Status      = openStatus,
            Is_Convert__c = false
        );

        Lead dontConvert = new Lead(
            FirstName   = 'Ben',
            LastName    = 'Hold',
            Company     = 'Beta LLC',
            Status      = openStatus,
            Is_Convert__c = false
        );

        insert new List<Lead>{ toConvert, dontConvert };

        // Act
        // Flip the checkbox ONLY for the first lead, touch a harmless field on the second.
        toConvert.Is_Convert__c = true; // <-- this should trigger conversion in after update
        dontConvert.Phone = '123456';   // <-- remains false; should NOT convert

        update new List<Lead>{ toConvert, dontConvert };

        // Assert
        // Re-query to get post-trigger state
        Map<Id, Lead> leads = new Map<Id, Lead>([
            SELECT Id, IsConverted, ConvertedAccountId, ConvertedOpportunityId, FirstName, LastName
            FROM Lead
            WHERE Id IN :new List<Id>{ toConvert.Id, dontConvert.Id }
        ]);

        Lead converted = leads.get(toConvert.Id);
        System.assertNotEquals(null, converted, 'Converted Lead should be present');
        System.assertEquals(true, converted.IsConverted, 'Lead with checkbox flip must be converted');
        System.assertNotEquals(null, converted.ConvertedAccountId, 'Converted Lead must have an Account');
        System.assertNotEquals(null, converted.ConvertedOpportunityId, 'Converted Lead must have an Opportunity');

        Lead untouched = leads.get(dontConvert.Id);
        System.assertNotEquals(null, untouched, 'Non-converted Lead should be present');
        System.assertEquals(false, untouched.IsConverted, 'Lead without checkbox flip must NOT be converted');

        // Extra sanity: the created Opportunity actually exists
        Opportunity opp = [
            SELECT Id, Name, AccountId, StageName
            FROM Opportunity
            WHERE Id = :converted.ConvertedOpportunityId
            LIMIT 1
        ];
        System.assertEquals(converted.ConvertedAccountId, opp.AccountId, 'Opportunity should belong to the converted Account');
        System.assert(opp.Name != null && opp.Name.length() > 0, 'Opportunity should have a name');
    }

    @IsTest
    static void testNoReconversion_whenAlreadyTrue() {
        // Arrange
        String openStatus = getOpenLeadStatus();

        Lead l = new Lead(
            FirstName   = 'Cara',
            LastName    = 'Once',
            Company     = 'Once Corp',
            Status      = openStatus,
            Is_Convert__c = false
        );
        insert l;

        // First flip -> converts
        l.Is_Convert__c = true;
        update l;

        // Capture post-conversion state
        l = [SELECT Id, IsConverted, ConvertedAccountId, ConvertedOpportunityId FROM Lead WHERE Id = :l.Id];
        System.assertEquals(true, l.IsConverted, 'Lead should be converted after first flip');
        Id accId = l.ConvertedAccountId;
        Id oppId = l.ConvertedOpportunityId;

        // Act: update some other field while Is_Convert__c remains true
        // (the handler should not try to reconvert since the flip condition is false)
        Account a = [SELECT Id, Name FROM Account WHERE Id = :accId LIMIT 1];
        a.Phone = '555-0100';
        update a; // harmless unrelated DML to ensure no dependency; not strictly necessary

        Lead lTouch = new Lead(Id = l.Id, Title = 'Changed Title');
        update lTouch;

        // Assert: still the same converted records (no duplicate opps etc.)
        Lead lAgain = [SELECT Id, IsConverted, ConvertedAccountId, ConvertedOpportunityId FROM Lead WHERE Id = :l.Id];
        System.assertEquals(true, lAgain.IsConverted, 'Lead remains converted');
        System.assertEquals(accId, lAgain.ConvertedAccountId, 'Account stays the same');
        System.assertEquals(oppId, lAgain.ConvertedOpportunityId, 'Opportunity stays the same');
    }
}