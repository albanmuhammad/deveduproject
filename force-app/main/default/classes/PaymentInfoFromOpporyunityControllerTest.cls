@isTest
private class PaymentInfoFromOpporyunityControllerTest {
    
    @TestSetup
    static void setupTestData() {
        // Create test Study Programs
        List<Study_Program__c> studyPrograms = new List<Study_Program__c>();
        for (Integer i = 0; i < 5; i++) {
            Study_Program__c sp = new Study_Program__c(
                Name = 'Test Study Program ' + i,
                Booking_Form_Price__c = 100000 + (i * 100000),
                Is_Active__c = true
            );
            studyPrograms.add(sp);
        }
        insert studyPrograms;
    }
    
    @isTest
    static void testCreatePaymentInfo_WithoutBookingFeePaid() {
        // Get study program
        Study_Program__c sp = [SELECT Id FROM Study_Program__c LIMIT 1];
        
        // Create opportunity without booking fee paid
        Opportunity opp = new Opportunity(
            Name = 'Test Opportunity Without Fee',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            Study_Program__c = sp.Id,
            Is_Booking_Fee_Paid__c = false
        );
        insert opp;
        
        Test.startTest();
        PaymentInfoFromOpporyunityController.createPaymentInfo(new List<Opportunity>{opp});
        Test.stopTest();
        
        // Verify no payment information created
        List<Payment_Information__c> payments = [
            SELECT Id 
            FROM Payment_Information__c 
            WHERE Application_Progress__c = :opp.Id
        ];
        
        System.assertEquals(0, payments.size(), 'Should not create payment record when booking fee is not paid');
    }
    
    @isTest
    static void testCreatePaymentInfo_WithoutStudyProgram() {
        // Create opportunity without study program
        Opportunity opp = new Opportunity(
            Name = 'Test Opportunity No Program',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            Is_Booking_Fee_Paid__c = true
        );
        insert opp;
        
        Test.startTest();
        PaymentInfoFromOpporyunityController.createPaymentInfo(new List<Opportunity>{opp});
        Test.stopTest();
        
        // Verify no payment information created
        List<Payment_Information__c> payments = [
            SELECT Id 
            FROM Payment_Information__c 
            WHERE Application_Progress__c = :opp.Id
        ];
        
        System.assertEquals(0, payments.size(), 'Should not create payment record without study program');
    }
    
    
    @isTest
    static void testCreatePaymentInfo_EmptyList() {
        Test.startTest();
        PaymentInfoFromOpporyunityController.createPaymentInfo(new List<Opportunity>());
        Test.stopTest();
        
        // Should complete without error
        List<Payment_Information__c> payments = [SELECT Id FROM Payment_Information__c];
        System.assertEquals(0, payments.size(), 'Should not create any payment records for empty list');
    }
    
    @isTest
    static void testCreatePaymentInfo_VerifyAmountFromStudyProgram() {
        // Get study program
        Study_Program__c sp = [SELECT Id, Booking_Form_Price__c FROM Study_Program__c LIMIT 1];
        Decimal expectedAmount = sp.Booking_Form_Price__c;
        
        // Create opportunity
        Opportunity opp = new Opportunity(
            Name = 'Test Amount Verification',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            Study_Program__c = sp.Id,
            Is_Booking_Fee_Paid__c = true
        );
        insert opp;
        
        Test.startTest();
        PaymentInfoFromOpporyunityController.createPaymentInfo(new List<Opportunity>{opp});
        Test.stopTest();
        
        // Verify amount matches study program price
        Payment_Information__c payment = [
            SELECT Amount__c 
            FROM Payment_Information__c 
            WHERE Application_Progress__c = :opp.Id
            LIMIT 1
        ];
        
        System.assertEquals(expectedAmount, payment.Amount__c, 'Payment amount should match study program booking price');
    }
}