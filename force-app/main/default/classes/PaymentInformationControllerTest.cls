@IsTest
private class PaymentInformationControllerTest {

    // ---------- Top-level helpers ----------
    private static List<PaymentInformationController.PaymentItemDTO> itemsOne(Decimal amt, Date due) {
        PaymentInformationController.PaymentItemDTO d = new PaymentInformationController.PaymentItemDTO();
        d.num = 1; d.amount = amt; d.dueDate = due;
        return new List<PaymentInformationController.PaymentItemDTO>{ d };
    }
    private static List<PaymentInformationController.PaymentItemDTO> itemsTwo(Decimal a1, Decimal a2, Date d1, Date d2) {
        PaymentInformationController.PaymentItemDTO x = new PaymentInformationController.PaymentItemDTO();
        x.num = 1; x.amount = a1; x.dueDate = d1;
        PaymentInformationController.PaymentItemDTO y = new PaymentInformationController.PaymentItemDTO();
        y.num = 2; y.amount = a2; y.dueDate = d2;
        return new List<PaymentInformationController.PaymentItemDTO>{ x, y };
    }

    private static Id findPersonAccountRtId() {
        List<RecordType> rts = [
            SELECT Id, DeveloperName, Name
            FROM RecordType
            WHERE SObjectType = 'Account'
        ];
        for (RecordType rt : rts) {
            String dn = rt.DeveloperName == null ? '' : rt.DeveloperName.toLowerCase();
            String nm = rt.Name == null ? '' : rt.Name.toLowerCase();
            if (dn.contains('person') || nm.contains('person')) return rt.Id;
        }
        return null;
    }

    private static Account makePersonAccount(String lastName, String mobile, String emailOpt) {
        Id rtId = findPersonAccountRtId();
        System.assertNotEquals(null, rtId,
            'This org has no Person Account RT; person-account specific tests will be skipped.');
        Account a = new Account();
        a.RecordTypeId = rtId;
        a.LastName = lastName;
        a.PersonMobilePhone = mobile;
        if (emailOpt != null) a.PersonEmail = emailOpt;
        insert a;
        return a;
    }

    private static Account makeBusinessAccount(String name) {
        Account a = new Account(Name = name);
        insert a;
        return a;
    }

    private static Opportunity makeOpp(Id accountId, Decimal amount, String stage) {
        Opportunity o = new Opportunity(
            Name      = 'REG-TEST-' + String.valueOf(Crypto.getRandomInteger()),
            StageName = stage,
            CloseDate = Date.today().addDays(7),
            Amount    = amount,
            AccountId = accountId
        );
        insert o;
        return o;
    }

    private static Payment_Channel__c makeChannel(String bank, String prefix) {
        Payment_Channel__c c = new Payment_Channel__c(
            Name = 'UT-PayChan ' + String.valueOf(Crypto.getRandomInteger()),
            VA_Prefix__c = prefix
        );
        if (bank != null) c.Payment_Channel_Bank__c = bank; // use only if valid in your org
        insert c;
        return c;
    }

    // ---------- savePayments: happy path (skips if no Person Accounts) ----------
    @IsTest
    static void testSavePayments_HappyPath_PersonAccount() {
        Id personRtId = findPersonAccountRtId();
        if (personRtId == null) {
            System.assert(true, 'Skipping happy-path: no Person Account RT found.');
            return;
        }

        Account pa = makePersonAccount('Tester', '+62 812-3456-789', null);
        Opportunity opp = makeOpp(pa.Id, 300000, 'Prospecting');
        Payment_Channel__c ch = makeChannel(null, '9886'); // leave bank null to avoid picklist traps

        List<PaymentInformationController.PaymentItemDTO> items =
            itemsTwo(100000, 200000, Date.today().addDays(3), Date.today().addDays(10));

        Test.startTest();
        PaymentInformationController.savePayments(
            opp.Id, items, ch.Id, 'Tuition Fee', 'Unpaid'
        );
        Test.stopTest();

        List<Payment_Information__c> rows = [
            SELECT Id, Amount__c, Due_Date__c, Payment_For__c,
                   Application_Progress__c, Virtual_Account_No__c,
                   Bank__c, Payment_Channel__c, Allocation__c
            FROM Payment_Information__c
            WHERE Application_Progress__c = :opp.Id
            ORDER BY CreatedDate ASC
        ];
        System.assertEquals(2, rows.size(), 'Two installments should be inserted');

        // Build expected VA dynamically from whatever prefix persisted
        Payment_Channel__c chSaved = [
            SELECT VA_Prefix__c
            FROM Payment_Channel__c
            WHERE Id = :ch.Id
        ];
        String savedPrefix = (chSaved.VA_Prefix__c == null) ? '' : chSaved.VA_Prefix__c.trim();
        String expectedDigits = '628123456789'; // digits of +62 812-3456-789
        String expectedVA = savedPrefix + expectedDigits;

        System.assertEquals(expectedVA, rows[0].Virtual_Account_No__c, 'VA number mismatch');
        if (!String.isBlank(savedPrefix)) {
            System.assert(rows[0].Virtual_Account_No__c.startsWith(savedPrefix), 'VA should start with prefix when present');
        }
        System.assert(rows[0].Virtual_Account_No__c.endsWith(expectedDigits), 'VA should end with digits-only phone');

        System.assertEquals('Tuition Fee', rows[0].Allocation__c);
        System.assertEquals(ch.Id, rows[0].Payment_Channel__c);
        System.assertEquals(100000, rows[0].Amount__c);
        System.assertEquals('Installment 1', rows[0].Payment_For__c);
        System.assertEquals(200000, rows[1].Amount__c);
        System.assertEquals('Installment 2', rows[1].Payment_For__c);
    }

    // ---------- savePayments: missing inputs (loose assertions) ----------
    @IsTest
    static void testSavePayments_Validation_MissingInputs() {
        // Null oppId
        Boolean threw;
        threw = false;
        try {
            PaymentInformationController.savePayments(
                null, itemsOne(100, Date.today()),
                Id.valueOf('001000000000000AAA'),
                'Tuition Fee', 'Unpaid'
            );
        } catch (Exception e) { threw = true; }
        System.assert(threw, 'Expected exception for null oppId');

        Account a = makeBusinessAccount('BizCo');
        Opportunity opp = makeOpp(a.Id, 1000, 'Prospecting');
        Payment_Channel__c ch = makeChannel(null, '77');

        // Null items
        threw = false;
        try {
            PaymentInformationController.savePayments(
                opp.Id, null, ch.Id, 'Tuition Fee', 'Unpaid'
            );
        } catch (Exception e) { threw = true; }
        System.assert(threw, 'Expected exception for null items');

        // Null channel
        threw = false;
        try {
            PaymentInformationController.savePayments(
                opp.Id, itemsOne(1000, Date.today()),
                null, 'Tuition Fee', 'Unpaid'
            );
        } catch (Exception e) { threw = true; }
        System.assert(threw, 'Expected exception for null channel');
    }

    // ---------- savePayments: bad amounts/dates/total (loose assertions) ----------
    @IsTest
    static void testSavePayments_Validation_BadAmounts_Dates_Total() {
        Account a = makeBusinessAccount('BizCo-2');
        Opportunity opp = makeOpp(a.Id, 1000, 'Prospecting');
        Payment_Channel__c ch = makeChannel(null, '55');

        // amount <= 0
        Boolean threw = false;
        try {
            PaymentInformationController.savePayments(
                opp.Id, itemsOne(0, Date.today()), ch.Id, 'Tuition Fee', 'Unpaid'
            );
        } catch (Exception e) { threw = true; }
        System.assert(threw, 'Expected exception for non-positive amount');

        // due date null
        PaymentInformationController.PaymentItemDTO d = new PaymentInformationController.PaymentItemDTO();
        d.num = 1; d.amount = 1000; d.dueDate = null;
        threw = false;
        try {
            PaymentInformationController.savePayments(
                opp.Id, new List<PaymentInformationController.PaymentItemDTO>{ d },
                ch.Id, 'Tuition Fee', 'Unpaid'
            );
        } catch (Exception e) { threw = true; }
        System.assert(threw, 'Expected exception for null due date');

        // sum mismatch (900 vs 1000)
        threw = false;
        try {
            PaymentInformationController.savePayments(
                opp.Id,
                itemsTwo(400, 500, Date.today(), Date.today().addDays(1)),
                ch.Id, 'Tuition Fee', 'Unpaid'
            );
        } catch (Exception e) { threw = true; }
        System.assert(threw, 'Expected exception for total mismatch');
    }

    // ---------- savePayments: phone validations (loose assertions) ----------
    @IsTest
    static void testSavePayments_Validation_PhoneMissingOrInvalid() {
        // Business Account (no PersonMobilePhone) -> blank phone
        Account noPhoneAcc = makeBusinessAccount('NoPhone Inc');
        Opportunity opp1 = makeOpp(noPhoneAcc.Id, 100, 'Prospecting');
        Payment_Channel__c ch = makeChannel(null, '11');

        Boolean threw = false;
        try {
            PaymentInformationController.savePayments(
                opp1.Id, itemsOne(100, Date.today()),
                ch.Id, 'Tuition Fee','Unpaid'
            );
        } catch (Exception e) { threw = true; }
        System.assert(threw, 'Expected exception for blank phone');

        // Person Account available → non-digit phone
        if (findPersonAccountRtId() != null) {
            Account pa = makePersonAccount('NoDigits', '+++++', null);
            Opportunity opp2 = makeOpp(pa.Id, 100, 'Prospecting');
            threw = false;
            try {
                PaymentInformationController.savePayments(
                    opp2.Id, itemsOne(100, Date.today()),
                    ch.Id, 'Tuition Fee', 'Unpaid'
                );
            } catch (Exception e) { threw = true; }
            System.assert(threw, 'Expected exception for non-digit-only phone');
        }
    }

    // ---------- advanceOppStage ----------
    @IsTest
    static void testAdvanceOppStage_Transitions() {
        Account acc = makeBusinessAccount('StageCo');
        Opportunity o1 = makeOpp(acc.Id, 500, 'Test Passed');
        Opportunity o2 = makeOpp(acc.Id, 500, 'Prospecting');

        Test.startTest();
        PaymentInformationController.advanceOppStage(o1.Id);
        PaymentInformationController.advanceOppStage(o2.Id);
        Test.stopTest();

        o1 = [SELECT StageName FROM Opportunity WHERE Id = :o1.Id];
        o2 = [SELECT StageName FROM Opportunity WHERE Id = :o2.Id];
        System.assertEquals('Payment', o1.StageName, 'Should flip from Test Passed to Payment');
        System.assertEquals('Prospecting', o2.StageName, 'Non-matching stage should stay unchanged');
    }

    // ---------- VF constructor & getters ----------
    @IsTest
    static void testVfConstructor_Init_Getters() {
        Account acc = makeBusinessAccount('VF Co');
        Opportunity opp = makeOpp(acc.Id, 1234, 'Prospecting');

        // Seed one Tuition Fee payment (do NOT set Name; likely auto-number)
        Payment_Information__c pi = new Payment_Information__c(
            Application_Progress__c = opp.Id,
            Amount__c = 1234,
            Due_Date__c = Date.today().addDays(5),
            Payment_For__c = 'Full Payment',
            Allocation__c = 'Tuition Fee'
        );
        insert pi;

        Test.startTest();
        Test.setCurrentPage(new PageReference('/apex/dummy'));
        ApexPages.currentPage().getParameters().put('oppId', opp.Id);
        PaymentInformationController ctrl = new PaymentInformationController();
        Test.stopTest();

        System.assertEquals(opp.Id, ctrl.oppId, 'oppId should be parsed from page params');
        System.assertNotEquals(null, ctrl.opp, 'Opp should be loaded');
        System.assertNotEquals(null, ctrl.payments, 'Payments should be loaded');
        System.assertEquals(1, ctrl.payments.size(), 'One tuition fee payment should be returned');

        System.assertEquals('', ctrl.getProgramLabel()); // we didn’t populate study/intake names
        System.assertEquals(acc.Name, ctrl.getAccName());
        System.assertEquals(opp.Amount, ctrl.totalSPP);
        System.assertEquals(opp.Amount - ctrl.sppTerbayar, ctrl.getSisaSPP());

        System.assert(!String.isBlank(ctrl.registrationNo), 'registrationNo should be populated from auto-number Name');
    }

    // ---------- VF constructor no page/param ----------
    @IsTest
    static void testVfConstructor_NoPageOrParam() {
        PaymentInformationController ctrl1 = new PaymentInformationController();
        System.assertEquals(null, ctrl1.oppId);

        Test.setCurrentPage(new PageReference('/apex/dummy2'));
        ApexPages.currentPage().getParameters().clear();
        PaymentInformationController ctrl2 = new PaymentInformationController();
        System.assertEquals(null, ctrl2.oppId);
    }

    // ---------- emailFormPayment: now runs in test mode (no exception expected) ----------
    @IsTest
    static void testEmailFormPayment_RunsInTestMode() {
        if (findPersonAccountRtId() == null) {
            System.assert(true, 'Skipping emailFormPayment test (no Person Account RT).');
            return;
        }
        Account pa = makePersonAccount('EmailPDF', '+62 811-0000-111', 'student@example.com');
        Opportunity opp = makeOpp(pa.Id, 1000, 'Prospecting');

        // Should NOT throw now because pdfBlob is stubbed in Test context
        PaymentInformationController.emailFormPayment(opp.Id);
        System.assert(true, 'emailFormPayment completed in test mode');
    }
}