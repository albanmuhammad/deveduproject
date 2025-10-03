@IsTest
private class OpportunityActiveFlagControllerTest {

    // Common helper to make a valid Opportunity quickly
    private static Opportunity makeOpp(Id accountId, String name, Boolean isActive) {
        return new Opportunity(
            Name = name,
            AccountId = accountId,
            StageName = 'Prospecting',   // default stage present in most orgs
            CloseDate = Date.today().addDays(30),
            Is_Active__c = isActive
        );
    }

    @IsTest
    static void testAfterInsert_newOppBecomesActive_andDeactivatesSiblings() {
        // Arrange
        Account acc = new Account(Name = 'Acme Co');
        insert acc;

        // Existing active sibling
        Opportunity siblingActive = makeOpp(acc.Id, 'Opp A (existing active)', true);
        insert siblingActive;

        // New opp to insert (even if false, controller should set it true and deactivate siblings)
        Opportunity newOpp = makeOpp(acc.Id, 'Opp B (new)', false);
        insert newOpp;

        // Act: simulate after-insert trigger
        OpportunityActiveFlagController.handleAfterInsert(new List<Opportunity>{ newOpp });

        // Assert
        // Re-query both
        List<Opportunity> check = [
            SELECT Id, Is_Active__c, Name
            FROM Opportunity
            WHERE Id IN :new List<Id>{ siblingActive.Id, newOpp.Id }
            ORDER BY Name
        ];
        // Expect newOpp active = true, siblingActive = false
        Map<Id, Opportunity> byId = new Map<Id, Opportunity>(check);
        System.assertEquals(true,  byId.get(newOpp.Id).Is_Active__c, 'Newly inserted opp must be active.');
        System.assertEquals(false, byId.get(siblingActive.Id).Is_Active__c, 'Existing active sibling must be deactivated.');
    }

    @IsTest
    static void testAfterUpdate_flipToTrue_deactivatesOtherActives() {
        // Arrange
        Account acc = new Account(Name = 'Beta LLC');
        insert acc;

        // One currently active opp (will be turned off)
        Opportunity oppActive = makeOpp(acc.Id, 'Opp Active', true);
        // One currently inactive opp (will be flipped to true)
        Opportunity oppToFlip = makeOpp(acc.Id, 'Opp To Flip', false);
        insert new List<Opportunity>{ oppActive, oppToFlip };

        // Prepare oldMap snapshot (before flip)
        Opportunity oldSnapshot = oppToFlip.clone(false, true, false, false);
        oldSnapshot.Id = oppToFlip.Id; // ensure Id is same
        Map<Id, Opportunity> oldMap = new Map<Id, Opportunity>{ oppToFlip.Id => oldSnapshot };

        // Act: flip false → true, perform the DML update first (like real after update),
        //      then invoke controller with new & old values.
        oppToFlip.Is_Active__c = true;
        update oppToFlip;
        OpportunityActiveFlagController.handleAfterUpdate(new List<Opportunity>{ oppToFlip }, oldMap);

        // Assert
        List<Opportunity> check = [
            SELECT Id, Is_Active__c, Name
            FROM Opportunity
            WHERE Id IN :new List<Id>{ oppActive.Id, oppToFlip.Id }
        ];
        Map<Id, Opportunity> byId = new Map<Id, Opportunity>(check);

        System.assertEquals(true,  byId.get(oppToFlip.Id).Is_Active__c,
            'Flipped opp should remain active after controller runs.');
        System.assertEquals(false, byId.get(oppActive.Id).Is_Active__c,
            'Previously active sibling must be deactivated.');
    }

    @IsTest
    static void testAfterUpdate_noFlip_doesNothing() {
        // Arrange
        Account acc = new Account(Name = 'Gamma Inc');
        insert acc;

        // Two actives (this “bad” state shouldn’t happen via your logic, but we test no-flip path)
        Opportunity opp1 = makeOpp(acc.Id, 'Opp1 stays true', true);
        Opportunity opp2 = makeOpp(acc.Id, 'Opp2 also true', true);
        insert new List<Opportunity>{ opp1, opp2 };

        // Touch opp1 without changing Is_Active__c (no flip false→true)
        Opportunity before = opp1.clone(false, true, false, false);
        before.Id = opp1.Id;
        Map<Id, Opportunity> oldMap = new Map<Id, Opportunity>{ opp1.Id => before };

        opp1.Description = 'Touched but still true';
        update opp1;

        // Act: simulate after-update with no flip
        OpportunityActiveFlagController.handleAfterUpdate(new List<Opportunity>{ opp1 }, oldMap);

        // Assert: since there was no flip, controller should not change anything
        List<Opportunity> check = [
            SELECT Id, Is_Active__c, Name
            FROM Opportunity
            WHERE Id IN :new List<Id>{ opp1.Id, opp2.Id }
            ORDER BY Name
        ];
        Map<Id, Opportunity> byId = new Map<Id, Opportunity>(check);
        System.assertEquals(true, byId.get(opp1.Id).Is_Active__c, 'Opp1 should remain true (no flip).');
        System.assertEquals(true, byId.get(opp2.Id).Is_Active__c, 'Opp2 should remain true because no deactivation should run.');
    }
}