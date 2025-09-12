import { LightningElement, api, track } from 'lwc';
import saveAccountDocument from '@salesforce/apex/AccountDocumentController.saveAccountDocument';

export default class lwcDocumentUpload extends LightningElement {
    @api recordId; // this is Account Id
    acceptedFormats = ['.pdf', '.jpg', '.jpeg', '.png'];

    @track documents = [
        { label: 'Rapor kelas 10', value: 'Rapor kelas 10', uploaded: false },
        { label: 'Rapor kelas 11', value: 'Rapor kelas 11', uploaded: false },
        { label: 'Rapor kelas 12', value: 'Rapor kelas 12', uploaded: false },
        { label: 'Scan KTP', value: 'Scan KTP', uploaded: false },
        { label: 'Scan Ijazah SMA', value: 'Scan Ijazah SMA', uploaded: false },
        { label: 'Scan Akte Kelahiran', value: 'Scan Akte Kelahiran', uploaded: false },
        { label: 'Scan Form Tata Tertib', value: 'Scan Form Tata Tertib', uploaded: false },
        { label: 'Scan Kartu Keluarga', value: 'Scan Kartu Keluarga', uploaded: false },
        { label: 'Scan Surat Sehat', value: 'Scan Surat Sehat', uploaded: false },
        { label: 'Lainnya', value: 'Lainnya', uploaded: false }
    ];

    handleUploadFinished(event) {
        const uploadedDocId = event.target.name; 
        this.documents = this.documents.map(doc => {
            if (doc.value === uploadedDocId) {
                return { ...doc, uploaded: true, contentDocumentId: event.detail.files[0].documentId };
            }
            return doc;
        });
    }

    async handleSave(event) {
        const docType = event.target.dataset.type;
        const selectedDoc = this.documents.find(d => d.value === docType);

        if (!selectedDoc || !selectedDoc.contentDocumentId) {
            return;
        }

        try {
            await saveAccountDocument({
                accountId: this.recordId,
                documentType: selectedDoc.value,
                contentDocumentId: selectedDoc.contentDocumentId
            });

            this.showToast('Success', `Document ${docType} saved to Account Document`, 'success');
        } catch (e) {
            this.showToast('Error', e.body ? e.body.message : e.message, 'error');
        }
    }

    showToast(title, message, variant) {
        const evt = new ShowToastEvent({
            title,
            message,
            variant
        });
        this.dispatchEvent(evt);
    }

    get decoratedDocuments() {
        return this.documents.map(d => ({
            ...d,
            statusLabel: d.uploaded ? 'Uploaded' : 'Not Uploaded',
            statusClass: d.uploaded ? 'slds-text-color_success' : 'slds-text-color_error',
            disabled: !d.uploaded   // 👈 here is the fix
        }));
    }

}
