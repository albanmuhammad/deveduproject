public with sharing class TestInformationController {

    @AuraEnabled(cacheable=true)
    public static List<Test_Information__c> getTodaysTests() {
        try {
            // Define the start and end of today to query the DateTime field
            Date today = Date.today();
            Datetime startOfDay = Datetime.newInstance(today.year(), today.month(), today.day(), 0, 0, 0);
            Datetime endOfDay = Datetime.newInstance(today.year(), today.month(), today.day(), 23, 59, 59);

            // Query using the start and end datetime variables
            return [
                SELECT Id, Name, Applicant__r.Name, Test_Schedule__c
                FROM Test_Information__c
                WHERE Is_Attend__c = false
                AND Test_Schedule__c >= :startOfDay
                AND Test_Schedule__c <= :endOfDay
                ORDER BY Test_Schedule__c ASC
            ];
        } catch (Exception e) {
            // Propagate exceptions to the LWC for user-friendly error handling.
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static String updateAttendance(List<Id> recordIds) {
        if (recordIds == null || recordIds.isEmpty()) {
            throw new AuraHandledException('No record IDs were provided for the update.');
        }

        try {
            List<Test_Information__c> testsToUpdate = new List<Test_Information__c>();
            for (Id recordId : recordIds) {
                testsToUpdate.add(new Test_Information__c(
                    Id = recordId,
                    Is_Attend__c = true
                ));
            }
            // Perform the DML operation.
            update testsToUpdate;
            return 'Success';
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
}