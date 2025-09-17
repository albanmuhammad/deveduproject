import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getRecord, getRecordNotifyChange } from 'lightning/uiRecordApi';
import { RefreshEvent } from 'lightning/refresh';
import getInitData from '@salesforce/apex/AccountDocumentController.getInitData';
import saveAccountDocument from '@salesforce/apex/AccountDocumentController.saveAccountDocument';
import verifyAccountDocument from '@salesforce/apex/AccountDocumentController.verifyAccountDocument';
import deleteAccountDocument from '@salesforce/apex/AccountDocumentController.deleteAccountDocument';

const FIELDS = [
    'Opportunity.AccountId',
    'Opportunity.Name',
    'Opportunity.RecordType.Name',
    'Opportunity.StageName'
];

export default class LwcDocumentUpload extends LightningElement {
    @api recordId;
    acceptedFormats = ['.pdf', '.jpg', '.jpeg', '.png'];
    @track opportunityId;
    @track accountId;
    @track opportunityName;
    @track isSchool = false;
    @track stageName;
    baseDocuments = [
        { label: 'Pas Foto 3x4', value: 'Pas Foto 3x4' },
        { label: 'Rapor 1', value: 'Rapor 1' },
        { label: 'Rapor 2', value: 'Rapor 2' },
        { label: 'Rapor 3', value: 'Rapor 3' },
        { label: 'Scan KTP', value: 'Scan KTP' },
        { label: 'Scan Ijazah', value: 'Scan Ijazah' },
        { label: 'Scan Akte Kelahiran', value: 'Scan Akte Kelahiran' },
        { label: 'Scan Form Tata Tertib', value: 'Scan Form Tata Tertib' },
        { label: 'Scan Kartu Keluarga', value: 'Scan Kartu Keluarga' },
        { label: 'Scan Surat Sehat', value: 'Scan Surat Sehat' },
        { label: 'Scan KTP Orang Tua', value: 'Scan KTP Orang Tua' },
        { label: 'Lainnya', value: 'Lainnya' }
    ];
    @track documents = [];

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredOpp({ data, error }) {
        if (error) {
            this.toast('Error', 'Failed to read Application Progress: ' + (error.body?.message || error.message), 'error');
            return;
        }
        if (data) {
            this.opportunityId = this.recordId;
            this.accountId = data.fields.AccountId.value;
            this.opportunityName = data.fields.Name.value;
            const rtName = data.fields.RecordType?.value?.fields?.Name?.value;
            this.isSchool = rtName === 'School';
            this.stageName = data.fields.StageName.value;
            this.init();
        }
    }

    get uploadParentId() {
        return this.opportunityId || this.recordId;
    }

    async init() {
        try {
            if (!this.accountId) {
                this.toast('Warning', 'This Application Progress has no Account. Please set Account first.', 'warning');
                this.documents = [];
                return;
            }
            const types = this.baseDocuments.map(d => d.value);
            const resp = await getInitData({
                accountId: this.accountId,
                opportunityId: this.opportunityId,
                documentTypes: types
            });
            let source = this.baseDocuments;
            if (resp.isSchool) {
                source = source.filter(d => d.value !== 'Scan KTP');
            } else {
                source = source.filter(d => d.value !== 'Scan KTP Orang Tua');
            }
            this.documents = source.map(d => {
                const status = resp.statusByType && resp.statusByType[d.value]
                    ? resp.statusByType[d.value]
                    : { uploaded: false, verified: false, contentDocumentId: null, documentLink: null };
                return {
                    label: d.label,
                    value: d.value,
                    uploaded: !!status.uploaded,
                    verified: !!status.verified,
                    contentDocumentId: status.contentDocumentId || null,
                    documentLink: status.documentLink || null
                };
            });
        } catch (e) {
            this.toast('Error', this.errMsg(e), 'error');
        }
    }

    async handleUploadFinished(event) {
        const docType = event.target.name;
        const files = event.detail?.files || [];
        if (!files.length) return;
        const contentDocumentId = files[0].documentId;
        try {
            await saveAccountDocument({
                accountId: this.accountId,
                opportunityId: this.opportunityId,
                initialParentId: this.uploadParentId,
                documentType: docType,
                contentDocumentId
            });
            this.toast('Success', `File for "${docType}" uploaded & renamed to ${docType}_${this.opportunityName}`, 'success');
            this.refreshRelatedLists();
            await this.init();
        } catch (e) {
            this.toast('Error', this.errMsg(e), 'error');
        }
    }

    async handleVerify(event) {
        const docType = event.target.dataset.type;
        const doc = this.documents.find(d => d.value === docType);
        if (!doc || !doc.uploaded) return;
        try {
            await verifyAccountDocument({
                accountId: this.accountId,
                opportunityId: this.opportunityId,
                documentType: docType,
                verified: true
            });
            this.toast('Success', `"${docType}" verified.`, 'success');
            this.refreshRelatedLists();
            await this.init();
        } catch (e) {
            this.toast('Error', this.errMsg(e), 'error');
        }
    }

    async handleDelete(event) {
        const docType = event.target.dataset.type;
        const doc = this.documents.find(d => d.value === docType);
        if (!doc || !doc.uploaded) return;
        try {
            await deleteAccountDocument({
                accountId: this.accountId,
                opportunityId: this.opportunityId,
                documentType: docType
            });
            this.toast('Success', `Document "${docType}" deleted.`, 'success');
            this.refreshRelatedLists();
            await this.init();
        } catch (e) {
            this.toast('Error', this.errMsg(e), 'error');
        }
    }

    refreshRelatedLists() {
        getRecordNotifyChange([{ recordId: this.recordId }]);
        this.dispatchEvent(new RefreshEvent());
    }

    get decoratedDocuments() {
        return this.documents.map(d => {
            let statusLabel = 'Not Uploaded';
            if (d.uploaded && !d.verified) statusLabel = 'Uploaded';
            if (d.verified) statusLabel = 'Verified';

            const statusClass =
                statusLabel === 'Verified'
                    ? 'uploaded'
                    : statusLabel === 'Uploaded'
                        ? 'slds-text-color_success'
                        : 'slds-text-color_error';

            let uploadDisabled = true;
            if (this.stageName === 'Registration') {
                uploadDisabled = d.value !== 'Pas Foto 3x4';
            } else if (this.stageName === 'Re-Registration') {
                uploadDisabled = d.value === 'Pas Foto 3x4';
            }

            const noVerifyTypes = ['Pas Foto 3x4', 'Lainnya'];
            const hasVerify = !noVerifyTypes.includes(d.value);

            return {
                ...d,
                statusLabel,
                statusClass,
                uploadDisabled,
                verifyDisabled: !d.uploaded || !!d.verified,
                hideVerify: !hasVerify,
                verifyLabel: d.verified ? 'Verified' : 'Verify',
                deleteDisabled: !d.uploaded
            };
        });
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
    errMsg(e) {
        return e?.body?.message || e?.message || 'Unexpected error';
    }
}