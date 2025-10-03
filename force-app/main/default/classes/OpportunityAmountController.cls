public with sharing class OpportunityAmountController {

    public static void handleAmountCalculation(List<Opportunity> newList, Map<Id, Opportunity> oldMap) {
        List<Opportunity> toUpdate = new List<Opportunity>();

        // Collect Ids
        Set<Id> batchIds = new Set<Id>();
        Set<Id> bspIds   = new Set<Id>();
        Set<Id> testInfoOppIds = new Set<Id>();

        for (Opportunity newOpp : newList) {
            Opportunity oldOpp = oldMap != null ? oldMap.get(newOpp.Id) : null;

            // Run only when stage just changed to "Test Passed"
            if (newOpp.StageName == 'Test Passed' &&
                (oldOpp == null || oldOpp.StageName != 'Test Passed')) {

                if (newOpp.Batch_Study_Program__c != null) {
                    bspIds.add(newOpp.Batch_Study_Program__c);
                }
                if (newOpp.Master_Batch__c != null) {
                    batchIds.add(newOpp.Master_Batch__c);
                }
                testInfoOppIds.add(newOpp.Id);
            }
        }

        if (testInfoOppIds.isEmpty()) return;

        // Query Batch Study Program → Application Fee + Intake
        Map<Id, Batch_Study_Program__c> bspMap = new Map<Id, Batch_Study_Program__c>(
            [SELECT Id, Study_Program_Intake__c,
                    Study_Program_Intake__r.Application_Fee__c
             FROM Batch_Study_Program__c
             WHERE Id IN :bspIds]
        );

        // Query Master Batch discount
        Map<Id, Master_Batches__c> batchMap = new Map<Id, Master_Batches__c>(
            [SELECT Id, Discount_Percentage__c
             FROM Master_Batches__c
             WHERE Id IN :batchIds]
        );

        // Query Test Information (linked to Opportunity)
        Map<Id, Test_Information__c> testInfoMap = new Map<Id, Test_Information__c>();
        for (Test_Information__c ti : [
            SELECT Id, Application_Progress__c, Test_Score__c
            FROM Test_Information__c
            WHERE Application_Progress__c IN :testInfoOppIds
        ]) {
            testInfoMap.put(ti.Application_Progress__c, ti);
        }


        // Query all available Test Discounts
        List<Test_Discount__c> allTestDiscounts = [
            SELECT Id, Name, Minimum_Test_Score__c, Discount_Percentage__c
            FROM Test_Discount__c
            ORDER BY Minimum_Test_Score__c ASC
        ];

        // Build updates
        for (Opportunity opp : newList) {
            Opportunity oldOpp = oldMap != null ? oldMap.get(opp.Id) : null;
            if (opp.StageName != 'Test Passed' ||
                (oldOpp != null && oldOpp.StageName == 'Test Passed')) continue;

            Decimal baseFee     = 0;
            Decimal batchDisc   = 0;
            Decimal testDisc    = 0;

            // From Batch Study Program → Intake fee
            if (opp.Batch_Study_Program__c != null && bspMap.containsKey(opp.Batch_Study_Program__c)) {
                Batch_Study_Program__c bsp = bspMap.get(opp.Batch_Study_Program__c);
                if (bsp.Study_Program_Intake__r != null) {
                    baseFee = bsp.Study_Program_Intake__r.Application_Fee__c != null ?
                              bsp.Study_Program_Intake__r.Application_Fee__c : 0;
                }
            }

            // Batch discount
            if (opp.Master_Batch__c != null && batchMap.containsKey(opp.Master_Batch__c)) {
                batchDisc = batchMap.get(opp.Master_Batch__c).Discount_Percentage__c != null ?
                            batchMap.get(opp.Master_Batch__c).Discount_Percentage__c : 0;
            }

            // Test discount (pick the best available one)
            if (testInfoMap.containsKey(opp.Id)) {
                Test_Information__c ti = testInfoMap.get(opp.Id);
                if (ti.Test_Score__c != null) {
                    Decimal bestDiscount = 0;
                    for (Test_Discount__c td : allTestDiscounts) {
                        System.debug('test disc name: ' + td.Name + 
                            ' test disc perc: ' + td.Discount_Percentage__c + 
                            ' test disc min score: ' + td.Minimum_Test_Score__c +
                            ' test score: ' + ti.Test_Score__c);
                        if (ti.Test_Score__c >= td.Minimum_Test_Score__c) {
                            if (td.Discount_Percentage__c != null && td.Discount_Percentage__c > bestDiscount) {
                                bestDiscount = td.Discount_Percentage__c;
                            }
                        }
                    }
                    testDisc = bestDiscount;
                    System.debug('test disc: ' + testDisc);
                    
                }
            }


            // Final amount = baseFee - (batchDiscount% + testDiscount%)
            // Base fee 20jt
            Decimal batchDiscountAmount = baseFee * (batchDisc / 100); // Potongan 10% -> 2jt
            Decimal amountBatchDiscounted = baseFee - batchDiscountAmount; // 20jt - 2jt = 18jt
            Decimal testDiscountAmount = amountBatchDiscounted * (testDisc / 100); // Potongan 10% -> 1,8jt
            Decimal finalAmount = amountBatchDiscounted - testDiscountAmount; // 18jt - 1,8jt = 16,2jt

            Opportunity upd = new Opportunity(Id = opp.Id, Amount = finalAmount);
            toUpdate.add(upd);
        }

        if (!toUpdate.isEmpty()) {
            
            update toUpdate;
        }
    }
}