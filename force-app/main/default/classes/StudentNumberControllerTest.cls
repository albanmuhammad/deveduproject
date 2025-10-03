@IsTest
private class StudentNumberControllerTest {

    /* ========== Helpers ========== */

    @testSetup
    static void setupData() {
        // Person Account record type (for PersonEmail usage elsewhere in org)
        RecordType paRt = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Account' AND IsPersonType = true
            LIMIT 1
        ];

        Account a = new Account(
            RecordTypeId = paRt.Id,
            FirstName = 'Stu',
            LastName  = 'Dent',
            PersonEmail = 'student@example.com'
        );
        insert a;

        // Admission period & intake (Admission_Period__r.Name must contain a 4-digit year)
        AdmissionPeriod__c ap = new AdmissionPeriod__c(Name = '2026/2027');
        insert ap;

        Master_Intake__c intake = new Master_Intake__c(
            Name = 'Main Intake',
            Admission_Period__c = ap.Id
        );
        insert intake;

        // Seed an opportunity not yet Closed Won
        Opportunity opp = new Opportunity(
            Name = 'App-001',
            AccountId = a.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(7),
            Master_Intake__c = intake.Id
        );
        insert opp;
    }

    private static Opportunity getOpp() {
        return [
            SELECT Id, AccountId, StageName, Master_Intake__c
                 , Account.Student_Number__c
            FROM Opportunity
            LIMIT 1
        ];
    }

    /* ========== Tests ========== */

    @IsTest
    static void assignsStudentNumber_onRealClosedWonUpdate() {
        // --- Setup: create Account, Intake with Admission Period 2025, and Opportunity
        Account acc = new Account(Name = 'Acme Student');
        insert acc;

        // Create intake and (optionally) admission period without hardcoding API names
        Id apId = createAdmissionPeriodForIntake(); // your schema-safe helper that sets Name='Admission 2025'

        Master_Intake__c intake = new Master_Intake__c(Name = 'Main Intake');
        // set lookup if it exists
        Map<String, Schema.SObjectField> intakeFields =
            Schema.getGlobalDescribe().get('Master_Intake__c').getDescribe().fields.getMap();
        if (intakeFields.containsKey('Admission_Period__c') && apId != null) {
            intake.put('Admission_Period__c', apId);
        }
        insert intake;

        Opportunity opp = new Opportunity(
            Name      = 'App-001',
            AccountId = acc.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(7),
            Master_Intake__c = intake.Id
        );
        insert opp;

        // --- Act: update to Closed Won to fire the trigger
        Test.startTest();
        opp = [SELECT Id, StageName FROM Opportunity WHERE Id = :opp.Id];
        opp.StageName = 'Closed Won';
        update opp; // let the trigger/handler invoke your StudentNumberController
        Test.stopTest();

        // --- Assert
        acc = [SELECT Id, Student_Number__c FROM Account WHERE Id = :acc.Id];
        System.assertNotEquals(null, acc.Student_Number__c, 'Student number should be generated');
        System.assert(acc.Student_Number__c.startsWith('13725'),
            'Expected prefix 13725 (137 + YY for 2025), got: ' + acc.Student_Number__c);
    }


    @IsTest
    static void doesNothingIfNotClosedWon() {
        Opportunity oldV = getOpp();

        Opportunity newV = oldV.clone(false, true, false, false);
        newV.StageName = 'Prospecting'; // no change to Closed Won

        Test.startTest();
        StudentNumberController.assignForClosedWon(
            new List<Opportunity>{ newV },
            new Map<Id, Opportunity>{ oldV.Id => oldV }
        );
        Test.stopTest();

        Account a = [
            SELECT Id, Student_Number__c
            FROM Account
            WHERE Id = :oldV.AccountId
        ];
        System.assertEquals(null, a.Student_Number__c,
            'Should not assign when stage did not become Closed Won');
    }

    // Creates a referenced Admission Period record for Master_Intake__c.Admission_Period__c
    // without hardcoding the object API name. Sets Name with a 4-digit year so StudentNumberController can read YY.
    private static Id createAdmissionPeriodForIntake() {
        // Describe the intake field
        Schema.SObjectType intakeType = Schema.getGlobalDescribe().get('Master_Intake__c');
        if (intakeType == null) return null;

        Map<String, Schema.SObjectField> fMap = intakeType.getDescribe().fields.getMap();
        if (!fMap.containsKey('Admission_Period__c')) return null;

        Schema.DescribeFieldResult f = fMap.get('Admission_Period__c').getDescribe();
        List<Schema.SObjectType> refs = f.getReferenceTo();
        if (refs == null || refs.isEmpty()) return null;

        // Use the first reference target — works even with namespaces
        Schema.SObjectType apType = refs[0];
        SObject ap = apType.newSObject();

        // Set Name if available; use a year your logic expects to become YY='25'
        Map<String, Schema.SObjectField> apFields = apType.getDescribe().fields.getMap();
        if (apFields.containsKey('Name')) {
            ap.put('Name', 'Admission 2025');
        }
        insert ap;
        return (Id) ap.get('Id');
    }

}