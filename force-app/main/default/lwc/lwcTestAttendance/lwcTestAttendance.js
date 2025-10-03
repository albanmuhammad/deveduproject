import { LightningElement, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import { subscribe, onError } from 'lightning/empApi';

// Apex
import getTodaysTests from '@salesforce/apex/TestInformationController.getTodaysTests';
import updateAttendance from '@salesforce/apex/TestInformationController.updateAttendance';

const COLUMNS = [
    { label: 'Test Information Name', fieldName: 'Name', type: 'text' },
    { label: 'Applicant', fieldName: 'ApplicantName', type: 'text' },
    { label: 'Study Program', fieldName: 'StudyProgram', type: 'text' },
    { label: 'Test Schedule', fieldName: 'FormattedSchedule', type: 'text' }
];

export default class LwcTestAttendance extends LightningElement {
    columns = COLUMNS;
    allRecords = [];
    records = [];
    error;
    errorText;
    wiredRecordsResult;
    selectedIds = [];
    isLoading = false;

    subscription = {};
    channelName = '/data/Test_Information__ChangeEvent'; // CDC channel

    // Wire data
    @wire(getTodaysTests)
    wiredTests(result) {
        this.wiredRecordsResult = result;
        if (result.data) {
            this.allRecords = result.data.map(record => ({
                ...record,
                ApplicantName: record.Applicant__r ? record.Applicant__r.Name : 'N/A',
                StudyProgram: record.Application_Progress__r?.Study_Program__r?.Name || 'N/A',
                FormattedSchedule: this.formatDateTime(record.Test_Schedule__c)
            }));
            this.records = [...this.allRecords];
            this.error = undefined;
        } else if (result.error) {
            this.error = result.error;
            this.errorText = this.getErrorMessage(result.error);
            this.records = [];
        }
    }

    // --- Lifecycle ---
    connectedCallback() {
        this.subscribeToCdc();
        this.registerErrorListener();
    }

    // --- CDC Subscription ---
    subscribeToCdc() {
        const messageCallback = (response) => {
            console.log('CDC Event received: ', JSON.stringify(response));
            refreshApex(this.wiredRecordsResult);
        };

        subscribe(this.channelName, -1, messageCallback).then(response => {
            console.log('Subscribed to channel: ', JSON.stringify(response.channel));
            this.subscription = response;
        });
    }

    registerErrorListener() {
        onError(error => {
            console.error('Streaming API error: ', JSON.stringify(error));
        });
    }

    // --- UI helpers ---
    get isButtonDisabled() {
        return this.selectedIds.length === 0 || this.isLoading;
    }

    get hasRecords() {
        return this.records && this.records.length > 0;
    }

    // --- Events ---
    handleSearch(event) {
        const searchKey = event.target.value.toLowerCase();
        if (!searchKey) {
            this.records = [...this.allRecords];
            return;
        }

        this.records = this.allRecords.filter(rec =>
            (rec.Name && rec.Name.toLowerCase().includes(searchKey)) ||
            (rec.ApplicantName && rec.ApplicantName.toLowerCase().includes(searchKey)) ||
            (rec.StudyProgram && rec.StudyProgram.toLowerCase().includes(searchKey)) ||
            (rec.FormattedSchedule && rec.FormattedSchedule.toLowerCase().includes(searchKey))
        );
    }

    handleRowSelection(event) {
        this.selectedIds = event.detail.selectedRows.map(row => row.Id);
    }

    async handleUpdate() {
        if (this.selectedIds.length === 0) {
            return;
        }
        this.isLoading = true;

        try {
            await updateAttendance({ recordIds: this.selectedIds });
            this.showToast('Success', 'Attendance marked successfully.', 'success');
            this.selectedIds = [];
            this.template.querySelector('lightning-datatable').selectedRows = [];
            await refreshApex(this.wiredRecordsResult);
        } catch (error) {
            this.showToast('Error', this.getErrorMessage(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // --- Helpers ---
    showToast(title, message, variant) {
        const event = new ShowToastEvent({ title, message, variant });
        this.dispatchEvent(event);
    }

    getErrorMessage(error) {
        if (error?.body?.message) {
            return error.body.message;
        }
        return 'An unknown error occurred.';
    }

    formatDateTime(dateTimeString) {
        if (!dateTimeString) return '';
        const options = {
            day: '2-digit',
            month: 'long',
            year: 'numeric',
            hour: '2-digit',
            minute: '2-digit',
            hour12: false
        };
        return new Intl.DateTimeFormat('en-GB', options).format(new Date(dateTimeString));
    }
}