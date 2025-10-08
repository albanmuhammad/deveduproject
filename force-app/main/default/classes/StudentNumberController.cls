public with sharing class StudentNumberController {
    public static void assignForClosedWon(List<Opportunity> newList,
                                          Map<Id, Opportunity> oldMap) {

        System.debug('>>> assignForClosedWon START, size=' + newList.size());

        Map<Id, Opportunity> winnersById = new Map<Id, Opportunity>();
        Set<Id> winnerOppIds = new Set<Id>();
        Set<Id> accountIds = new Set<Id>();

        for (Opportunity o : newList) {
            Opportunity oldRec = (oldMap == null) ? null : oldMap.get(o.Id);
            Boolean justWon = (o.StageName == 'Closed Won') &&
                              (oldRec == null || oldRec.StageName != 'Closed Won');
            if (justWon && o.AccountId != null) {
                winnersById.put(o.Id, o);
                winnerOppIds.add(o.Id);
                accountIds.add(o.AccountId);
                System.debug('>>> Opportunity ' + o.Id + ' just became Closed Won, Account=' + o.AccountId);
            }
        }
        if (winnerOppIds.isEmpty()) {
            System.debug('>>> No winners found, returning');
            return;
        }

        Map<Id, String> accountToYY = new Map<Id, String>();
        for (Opportunity o : [
            SELECT Id, AccountId, Master_Intake__r.Admission_Period__c,
                     Master_Intake__r.Admission_Period__r.Name
            FROM Opportunity
            WHERE Id IN :winnerOppIds
        ]) {
            System.debug('>>> Opp ' + o.Id + ' Admission_Period__c = ' + o.Master_Intake__r.Admission_Period__c + 
                         ' Name=' + (o.Master_Intake__r == null ? null : o.Master_Intake__r.Admission_Period__r.Name));
            String yy = extractTwoDigitYear(o.Master_Intake__r == null ? null
                               : o.Master_Intake__r.Admission_Period__r.Name);
            System.debug('>>> Extracted YY=' + yy);
            if (!String.isBlank(yy) && o.AccountId != null) {
                accountToYY.put(o.AccountId, yy);
            }
        }
        if (accountToYY.isEmpty()) {
            System.debug('>>> No YY extracted, returning');
            return;
        }

        Map<Id, Account> accMap = new Map<Id, Account>(
            [SELECT Id, Student_Number__c
             FROM Account
             WHERE Id IN :accountIds
             FOR UPDATE]
        );
        System.debug('>>> Accounts to update: ' + accMap.keySet());

        Set<String> existing = new Set<String>();
        for (Account a : [
            SELECT Student_Number__c
            FROM Account
            WHERE Student_Number__c != null
        ]) {
            existing.add(a.Student_Number__c);
        }
        System.debug('>>> Existing student numbers loaded=' + existing.size());

        List<Account> toUpdate = new List<Account>();
        for (Id accId : accountIds) {
            Account a = accMap.get(accId);
            if (a == null) continue;
            if (!String.isBlank(a.Student_Number__c)) continue;
            String yy = accountToYY.get(accId);
            System.debug('>>> For Account ' + accId + ' got YY=' + yy);
            if (String.isBlank(yy)) continue;

            String candidate;
            Integer tries = 0;
            do {
                candidate = '137' + yy + randomFiveDigits();
                tries++;
            } while (existing.contains(candidate) && tries < 10);

            System.debug('>>> Candidate for ' + accId + ' = ' + candidate);
            a.Student_Number__c = candidate;
            existing.add(candidate);
            toUpdate.add(a);
        }

        if (!toUpdate.isEmpty()) {
            Database.SaveResult[] results = Database.update(toUpdate, false);
            for (Integer i = 0; i < results.size(); i++) {
                if (!results[i].isSuccess()) {
                    System.debug('>>> Update failed for ' + toUpdate[i].Id + ' Errors=' + results[i].getErrors());
                } else {
                    System.debug('>>> Update SUCCESS for ' + toUpdate[i].Id + ' StudentNumber=' + toUpdate[i].Student_Number__c);
                }
            }
        }
    }

    private static String extractTwoDigitYear(String admissionPeriod) {
        System.debug('>>> extractTwoDigitYear called with=' + admissionPeriod);
        if (String.isBlank(admissionPeriod)) return null;
        Matcher m = Pattern.compile('(\\d{4})').matcher(admissionPeriod);
        if (m.find()) {
            String yyyy = m.group(1);
            System.debug('>>> Found year ' + yyyy);
            return yyyy.substring(2, 4);
        }
        return null;
    }

    private static String randomFiveDigits() {
        Integer n = Math.mod(Math.abs(Crypto.getRandomInteger()), 100000);
        String s = String.valueOf(n);
        while (s.length() < 5) s = '0' + s;
        return s;
    }
}