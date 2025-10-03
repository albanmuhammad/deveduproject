@IsTest
private class AccountDocumentControllerTest {

    // ===== Picklist helpers (key change) =====

    private static List<String> getDocTypesFromOrg() {
        Schema.DescribeFieldResult dfr =
            Account_Document__c.Document_Type__c.getDescribe();
        List<String> vals = new List<String>();
        for (Schema.PicklistEntry pe : dfr.getPicklistValues()) {
            if (pe.isActive()) vals.add(pe.getValue());
        }
        return vals;
    }

    // Return at least one type (throws a clear error if none exist)
    private static String requireType1() {
        List<String> vals = getDocTypesFromOrg();
        System.assert(vals.size() > 0,
            'Your org has 0 active values for Account_Document__c.Document_Type__c. ' +
            'Please add at least one picklist value in Setup > Object Manager > Account Document > Fields & Relationships.');
        return vals[0];
    }

    // Return a second type if available; otherwise repeat the first one (tests that need two will adapt)
    private static String pickType2(String type1) {
        List<String> vals = getDocTypesFromOrg();
        for (String v : vals) if (v != type1) return v;
        return type1; // fallback: only one value exists
    }

    // ===== Generic helpers =====

    private static Id getOppRecordTypeIdSchoolIfExists() {
        List<RecordType> rts = [
            SELECT Id, Name, DeveloperName, SobjectType
            FROM RecordType
            WHERE SobjectType = 'Opportunity'
              AND (Name = 'School' OR DeveloperName = 'School')
            LIMIT 1
        ];
        return rts.isEmpty() ? null : rts[0].Id;
    }

    private static Opportunity makeOpp(Account a, Id recordTypeId, String name) {
        Opportunity o = new Opportunity(
            Name = name,
            AccountId = a.Id,
            StageName = 'Prospecting',
            CloseDate = System.today().addDays(30)
        );
        if (recordTypeId != null) o.RecordTypeId = recordTypeId;
        insert o;
        return o;
    }

    private static Account makeAccount(String name) {
        Account a = new Account(Name = name);
        insert a;
        return a;
    }

    private static Account_Document__c makeDoc(Id accId, Id oppId, String docType, Boolean verified, String linkOpt) {
        Account_Document__c d = new Account_Document__c(
            Account__c = accId,
            Application_Progress__c = oppId,
            Document_Type__c = docType,
            Verified__c = verified
        );
        if (linkOpt != null) d.Document_Link__c = linkOpt;
        insert d;
        return d;
    }

    private static Id createContentDocument(String title, String body) {
        ContentVersion cv = new ContentVersion(
            Title = title,
            PathOnClient = title + '.txt',
            VersionData = Blob.valueOf(body),
            IsMajorVersion = true
        );
        insert cv;

        cv = [
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE Id = :cv.Id
            LIMIT 1
        ];
        return cv.ContentDocumentId;
    }

    // ===== Tests =====

    @IsTest
    static void testGetInitData_LegacyAndPerOppPickingAndLinkBackfill() {
        String type1 = requireType1();
        String type2 = pickType2(type1);

        Account a = makeAccount('Acme Parent');
        Id schoolRtId = getOppRecordTypeIdSchoolIfExists();
        Opportunity o = makeOpp(a, schoolRtId, 'App 001');

        // If org only has one picklist value, we still run — both entries will use the same type.
        List<String> types = (type1 == type2)
            ? new List<String>{ type1 }
            : new List<String>{ type1, type2 };

        // Legacy doc for type1 (no Application_Progress__c)
        Account_Document__c legacyDoc = makeDoc(a.Id, null, type1, false, null);

        // Per-opportunity doc for type2 (or type1 if only one value exists)
        Account_Document__c perOppDoc = makeDoc(a.Id, o.Id, type2, true, null);

        // Link content to legacyDoc only (to test link backfill)
        Id cdocLegacy = createContentDocument('legacyTitle', 'legacy body');
        insert new ContentDocumentLink(
            ContentDocumentId = cdocLegacy,
            LinkedEntityId    = legacyDoc.Id,
            ShareType         = 'V',
            Visibility        = 'AllUsers'
        );

        System.Test.startTest();
        AccountDocumentController.InitResp resp =
            AccountDocumentController.getInitData(a.Id, o.Id, types);
        System.Test.stopTest();

        System.assertNotEquals(null, resp, 'InitResp should not be null');
        System.assertEquals('App 001', resp.opportunityName, 'Opportunity name mapped');

        Boolean expectedIsSchool = (schoolRtId != null);
        System.assertEquals(expectedIsSchool, resp.isSchool, 'isSchool should reflect real RT presence');

        // type1: should pick legacy, uploaded=true & link backfilled
        AccountDocumentController.DocStatus st1 = resp.statusByType.get(type1);
        System.assertNotEquals(null, st1, 'type1 status exists');
        System.assertEquals(true, st1.uploaded, 'Legacy type1 has a file');
        System.assertEquals(false, st1.verified, 'Legacy type1 verified=false');
        System.assertEquals(cdocLegacy, st1.contentDocumentId, 'type1 ContentDocumentId returned');
        System.assert(st1.documentLink != null && st1.documentLink.contains('/lightning/r/ContentDocument/'),
            'type1 link should be backfilled with Lightning URL');

        if (type1 != type2) {
            // type2: pick per-opp (verified=true, no file yet)
            AccountDocumentController.DocStatus st2 = resp.statusByType.get(type2);
            System.assertNotEquals(null, st2, 'type2 status exists');
            System.assertEquals(false, st2.uploaded, 'Per-opp type2 has no file yet');
            System.assertEquals(true, st2.verified, 'Per-opp type2 verified=true');
            System.assertEquals(null, st2.contentDocumentId, 'No file yet for type2');
        }
    }

    @IsTest
    static void testSaveAndVerifyAndDelete_Flow() {
        String type1 = requireType1();

        Account a = makeAccount('Beta Co');
        Id schoolRtId = getOppRecordTypeIdSchoolIfExists();
        Opportunity o = makeOpp(a, schoolRtId, 'App 002');

        Id cdoc = createContentDocument('incomingDoc', 'doc body');

        // SAVE
        System.Test.startTest();
        AccountDocumentController.saveAccountDocument(a.Id, o.Id, null, type1, cdoc);
        System.Test.stopTest();

        Account_Document__c created = [
            SELECT Id, Name, Account__c, Application_Progress__c,
                   Document_Type__c, Verified__c, Document_Link__c
            FROM Account_Document__c
            WHERE Account__c = :a.Id
              AND Application_Progress__c = :o.Id
              AND Document_Type__c = :type1
            LIMIT 1
        ];
        System.assertEquals(type1 + ' App 002', created.Name, 'Name pattern: <type> <opp name>');
        System.assertEquals(false, created.Verified__c, 'saveAccountDocument resets to verified=false');
        System.assert(created.Document_Link__c != null && created.Document_Link__c.contains('/lightning/r/ContentDocument/'),
            'Link set to lightning ContentDocument view');

        ContentDocument cd = [
            SELECT Id, Title FROM ContentDocument WHERE Id = :cdoc LIMIT 1
        ];
        System.assertEquals(type1 + '_App 002', cd.Title, 'ContentDocument renamed with type + opp');

        ContentVersion cv = [
            SELECT Id, Title, VersionNumber
            FROM ContentVersion
            WHERE ContentDocumentId = :cdoc
            ORDER BY VersionNumber DESC
            LIMIT 1
        ];
        System.assertEquals(type1 + '_App 002', cv.Title, 'Latest ContentVersion renamed');

        // VERIFY
        System.Test.startTest();
        AccountDocumentController.verifyAccountDocument(a.Id, o.Id, type1, true);
        System.Test.stopTest();

        Account_Document__c chk = [
            SELECT Id, Verified__c
            FROM Account_Document__c WHERE Id = :created.Id
        ];
        System.assertEquals(true, chk.Verified__c, 'verifyAccountDocument sets verified=true');

        // DELETE
        System.Test.startTest();
        AccountDocumentController.deleteAccountDocument(a.Id, o.Id, type1);
        System.Test.stopTest();

        Integer left = [
            SELECT COUNT()
            FROM Account_Document__c
            WHERE Account__c = :a.Id
              AND Application_Progress__c = :o.Id
              AND Document_Type__c = :type1
        ];
        System.assertEquals(0, left, 'Logical document deleted');

        Integer leftDocs = [
            SELECT COUNT() FROM ContentDocument WHERE Id = :cdoc
        ];
        System.assertEquals(0, leftDocs, 'ContentDocument deleted by controller');
    }

    @IsTest
    static void testFindPreference_LegacyVsExact() {
        String type1 = requireType1();

        Account a = makeAccount('Gamma Co');
        Opportunity o1 = makeOpp(a, null, 'App A');
        Opportunity o2 = makeOpp(a, null, 'App B');

        // Legacy doc (NULL Application_Progress__c)
        Account_Document__c legacy = makeDoc(a.Id, null, type1, false, null);

        // Saving for o1 should use legacy slot (no exact per-opp record exists)
        Id cdoc1 = createContentDocument('cv1', 'x1');
        System.Test.startTest();
        AccountDocumentController.saveAccountDocument(a.Id, o1.Id, null, type1, cdoc1);
        System.Test.stopTest();

        Account_Document__c afterSave1 = [
            SELECT Id, Application_Progress__c, Document_Link__c
            FROM Account_Document__c
            WHERE Id = :legacy.Id
            LIMIT 1
        ];
        System.assertNotEquals(null, afterSave1.Document_Link__c,
            'Legacy slot was used and link populated by saveAccountDocument');

        // Now create exact per-opp doc for o2 and attach a different file
        Account_Document__c perOpp = makeDoc(a.Id, o2.Id, type1, true, null);
        Id cdoc2 = createContentDocument('cv2', 'x2');
        insert new ContentDocumentLink(
            ContentDocumentId = cdoc2,
            LinkedEntityId    = perOpp.Id,
            ShareType         = 'V',
            Visibility        = 'AllUsers'
        );

        List<String> types = new List<String>{ type1 };

        System.Test.startTest();
        AccountDocumentController.InitResp resp = AccountDocumentController.getInitData(a.Id, o2.Id, types);
        System.Test.stopTest();

        AccountDocumentController.DocStatus st = resp.statusByType.get(type1);
        System.assertNotEquals(null, st, 'Doc type status present');
        System.assertEquals(true, st.uploaded, 'Per-opp has file');
        System.assertEquals(cdoc2, st.contentDocumentId, 'Exact per-opp doc preferred over legacy');
    }

    @IsTest
    static void testGuardClauses_GetInitData_NoAccountOrEmptyTypes() {
        System.Test.startTest();
        AccountDocumentController.InitResp r1 = AccountDocumentController.getInitData(null, null, null);
        AccountDocumentController.InitResp r2 = AccountDocumentController.getInitData(null, null, new List<String>());
        System.Test.stopTest();

        System.assertEquals(false, r1.isSchool, 'Default false');
        System.assertEquals('', r1.opportunityName, 'Default empty');
        System.assertEquals(0, r1.statusByType.size(), 'No types');

        System.assertEquals(false, r2.isSchool, 'Default false');
        System.assertEquals('', r2.opportunityName, 'Default empty');
        System.assertEquals(0, r2.statusByType.size(), 'No types');
    }

    @IsTest
    static void testGuardClauses_Save_And_Verify_And_Delete_Errors() {
        String type1 = requireType1();
        Account a = makeAccount('Delta Co');

        // Save: missing account -> error
        Boolean threw1 = false;
        try {
            AccountDocumentController.saveAccountDocument(null, null, null, type1, Id.valueOf('005000000000000AAA'));
        } catch (Exception e) { threw1 = true; }
        System.assertEquals(true, threw1, 'Account required error');

        // Save: missing params -> error
        Boolean threw2 = false;
        try {
            AccountDocumentController.saveAccountDocument(a.Id, null, null, null, null);
        } catch (Exception e) { threw2 = true; }
        System.assertEquals(true, threw2, 'Missing params error');

        // Verify: no doc present -> error
        Boolean threw3 = false;
        try {
            AccountDocumentController.verifyAccountDocument(a.Id, null, 'NOT_EXISTS', true);
        } catch (Exception e) { threw3 = true; }
        System.assertEquals(true, threw3, 'No document to verify error');

        // Delete: no doc present -> error
        Boolean threw4 = false;
        try {
            AccountDocumentController.deleteAccountDocument(a.Id, null, 'NOT_EXISTS');
        } catch (Exception e) { threw4 = true; }
        System.assertEquals(true, threw4, 'No document to delete error');
    }
}