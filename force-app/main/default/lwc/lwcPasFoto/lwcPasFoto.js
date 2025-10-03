import { LightningElement, api, wire } from 'lwc';
import getPasFotoVersionId from '@salesforce/apex/OpportunityPasFotoController.getPasFotoVersionId';

export default class PasFotoCard extends LightningElement {
    @api recordId;
    imageUrl;
    error;

    @wire(getPasFotoVersionId, { recordId: '$recordId' })
    wiredVersion({ data, error }) {
        if (data) {
            this.error = undefined;
            // build a URL that works in <img src="">
            this.imageUrl = `/sfc/servlet.shepherd/version/download/${data}`;
        } else if (error) {
            this.error = error;
            this.imageUrl = undefined;
            // keep a console error for debugging
            // eslint-disable-next-line no-console
            console.error('Error loading Pas Foto:', error);
        }
    }

    get noImage() {
        return !this.imageUrl && !this.error;
    }
}