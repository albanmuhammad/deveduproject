import { LightningElement, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';

// Import Apex methods
import getTodaysTests from '@salesforce/apex/TestInformationController.getTodaysTests';
import updateAttendance from '@salesforce/apex/TestInformationController.updateAttendance';

// Define columns for the datatable
const COLUMNS = [
    { label: 'Test Information Name', fieldName: 'Name', type: 'text' },
    { label: 'Applicant', fieldName: 'ApplicantName', type: 'text' },
    { label: 'Test Schedule', fieldName: 'Test_Schedule__c', type: 'datetime' }
];

export default class LwcTestAttendance extends LightningElement {
    columns = COLUMNS;
    records;
    error;
    errorText;
    wiredRecordsResult;
    selectedIds = [];
    isLoading = false;

    // Wire service to fetch data from Apex controller
    @wire(getTodaysTests)
    wiredTests(result) {
        this.wiredRecordsResult = result; // Cache the result for refreshApex
        if (result.data) {
            // Flatten related record data for the datatable
            this.records = result.data.map(record => ({
                ...record,
                ApplicantName: record.Applicant__r ? record.Applicant__r.Name : 'N/A'
            }));
            this.error = undefined;
        } else if (result.error) {
            this.error = result.error;
            this.errorText = this.getErrorMessage(result.error);
            this.records = undefined;
        }
    }

    // Getter to disable the button when no rows are selected or during loading
    get isButtonDisabled() {
        return this.selectedIds.length === 0 || this.isLoading;
    }

    // Getter to check if there are records to display
    get hasRecords() {
        return this.records && this.records.length > 0;
    }

    // Event handler for row selection in the datatable
    handleRowSelection(event) {
        this.selectedIds = event.detail.selectedRows.map(row => row.Id);
    }

    // Click handler for the 'Mark as Attended' button
    async handleUpdate() {
        if (this.selectedIds.length === 0) {
            return;
        }
        this.isLoading = true;

        try {
            await updateAttendance({ recordIds: this.selectedIds });
            this.showToast('Success', 'Attendance marked successfully.', 'success');
            
            // Clear selection and refresh the datatable
            this.selectedIds = [];
            this.template.querySelector('lightning-datatable').selectedRows = [];
            await refreshApex(this.wiredRecordsResult);

        } catch (error) {
            this.showToast('Error', this.getErrorMessage(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // Helper to show toast messages
    showToast(title, message, variant) {
        const event = new ShowToastEvent({ title, message, variant });
        this.dispatchEvent(event);
    }

    // Helper to parse different Salesforce error structures
    getErrorMessage(error) {
        if (error) {
            if (error.body && error.body.message) {
                return error.body.message;
            }
            return 'An unknown error occurred.';
        }
        return 'No error details available.';
    }
}