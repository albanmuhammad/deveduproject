@IsTest
private class QrFileControllerTest {
    // PNG 1x1 transparan (valid) tanpa prefix data-uri
    private static final String PNG_1x1_BASE64 =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMBAeJr3WQAAAAASUVORK5CYII=';

    @IsTest
    static void testSavePng_success_withFileName() {
        Account acc = new Account(Name = 'Parent For QR');
        insert acc;

        Test.startTest();
        Id docId = QrFileController.savePng(
            acc.Id,
            PNG_1x1_BASE64,
            'my-qr.png'
        );
        Test.stopTest();

        System.assertNotEquals(null, docId, 'ContentDocumentId harus terisi');

        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId, LinkedEntityId, ShareType, Visibility
            FROM ContentDocumentLink
            WHERE ContentDocumentId = :docId
        ];
        System.assertEquals(1, links.size(), 'Harus ada 1 CDL');
        System.assertEquals(acc.Id, links[0].LinkedEntityId);
        System.assertEquals('V', links[0].ShareType);
        System.assertEquals('AllUsers', links[0].Visibility);
    }

    @IsTest
    static void testSavePng_success_defaultFileName() {
        Account acc = new Account(Name = 'Parent Default Filename');
        insert acc;

        Test.startTest();
        Id docId = QrFileController.savePng(
            acc.Id,
            PNG_1x1_BASE64,
            null // harus jatuh ke 'qr.png'
        );
        Test.stopTest();

        System.assertNotEquals(null, docId);

        Integer cdlCount = [
            SELECT COUNT() FROM ContentDocumentLink
            WHERE ContentDocumentId = :docId AND LinkedEntityId = :acc.Id
        ];
        System.assertEquals(1, cdlCount);
    }

    @IsTest
    static void testSavePng_missingParams_throwAuraHandledException() {
        Account acc = new Account(Name = 'Parent Missing Params');
        insert acc;

        // base64 kosong
        try {
            Test.startTest();
            QrFileController.savePng(acc.Id, '', 'x.png');
            Test.stopTest();
            System.assert(false, 'Harusnya throw AuraHandledException (base64 kosong)');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('wajib diisi'));
        }

        // parentId kosong
        try {
            Test.startTest();
            QrFileController.savePng(null, PNG_1x1_BASE64, 'x.png');
            Test.stopTest();
            System.assert(false, 'Harusnya throw AuraHandledException (parentId kosong)');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('wajib diisi'));
        }
    }
}