import { LightningElement, api, track, wire } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { RefreshEvent } from 'lightning/refresh';
import { getRecord, getFieldValue, getRecordNotifyChange } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import savePayments from '@salesforce/apex/PaymentInformationController.savePayments';
import AMOUNT_FIELD from '@salesforce/schema/Opportunity.Amount';
import advanceOppStage from '@salesforce/apex/PaymentInformationController.advanceOppStage';


const FIELDS = [AMOUNT_FIELD];

const COLUMNS = [
  { label: 'Payment', fieldName: 'label', type: 'text', cellAttributes: { alignment: 'left' } },
  { label: 'Amount', fieldName: 'amount', type: 'number', editable: true, typeAttributes: { step: '1' } },
  { label: 'Due Date', fieldName: 'dueDate', type: 'date-local', editable: true }
];

export default class GeneratePaymentInfoAction extends LightningElement {
  @api recordId;
  @track paymentType = 'full';
  @track tenor = null;
  @track rows = [];
  @track draftValues = [];
  @track paymentChannelId = null;
  columns = COLUMNS;

  _didAutoPreview = false;              

  opp;  

  @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
  wiredOpp(value) {
    this.opp = value;
    if (value?.data && !this._didAutoPreview) {
      this._didAutoPreview = true;
      this.previewPlan();               // ⟵ auto-generate “Full Payment”
    }
  }
  get amount() { return getFieldValue(this.opp.data, AMOUNT_FIELD) || 0; }

  // --- UI helpers
  get paymentOptions() {
    return [{ label:'Full payment', value:'full' }, { label:'Installment', value:'installment' }];
  }
  get tenorOptions() { return [2,4,8,12].map(n => ({ label: `${n}x`, value: n })); }
  get isInstallment() { return this.paymentType === 'installment'; }
  get totalRows() { return this.rows.length; }
  get sum() { return this.rows.reduce((s,r) => s + Number(r.amount || 0), 0); }
  get hasDiff() { return this.sum !== Number(this.amount || 0); }
  get diff() { return Number(this.amount || 0) - this.sum; }
  get saveDisabled() {
    
    return (
      this.rows.length === 0 ||
      this.hasDiff ||
      this.rows.some(r => !r.dueDate || r.amount <= 0) ||
      !this.paymentChannelId
    );
  }
  get amountFormatted() { return new Intl.NumberFormat('id-ID').format(this.amount); }
  get sumFormatted() { return new Intl.NumberFormat('id-ID').format(this.sum); }
  get diffFormatted() { return new Intl.NumberFormat('id-ID').format(this.diff); }

  onPaymentChannelChange(e) {
      console.log(e);
      this.paymentChannelId = e.detail.recordId;
      console.log('haha',this.paymentChannelId )
  }

onTypeChange(e) {
  this.paymentType = e.detail.value;

  if (this.paymentType === 'full') {
    this.tenor = null;          
    this.previewPlan();         
  } else {
    // installment dipilih
    this.rows = [];             
    this.draftValues = [];
    if (this.tenor) {           
      this.previewPlan();
    }
  }
}
onTenorChange(e) {
  this.tenor = parseInt(e.detail.value, 10);
  this.previewPlan();           
}

  // Generate preview rows
  previewPlan() {
    const total = Number(this.amount || 0);
    if (!total || total <= 0) {
        this.rows = [];
        this.draftValues = [];
        this.toast('Error','Amount Opportunity harus > 0','error');
        return;
    }

    if (this.paymentType === 'full') {
        this.rows = [ this.makeRow('Full Payment', 1, total, this.datePlusMonthsOn28(1)) ];
    } else {
        if (!this.tenor) { 
        this.rows = [];          
        this.draftValues = [];
        return; 
        }
        const base = Math.floor(total / this.tenor);
        const remainder = total - (base * this.tenor);

        const newRows = [];
        for (let i = 0; i < this.tenor; i++) {
        let amt = base;
        if (i === this.tenor - 1) amt += remainder; 
        newRows.push(this.makeRow(`Installment ${i+1}`, i+1, amt, this.datePlusMonthsOn28(i+1)));
        }
        this.rows = newRows;
    }
    this.draftValues = [];
    }


  // inline edit handler
  handleDraftSave(e) {
    const updates = e.detail.draftValues; 
    const map = new Map(this.rows.map(r => [r.id, r]));
    updates.forEach(d => {
      const r = map.get(d.id);
      if (!r) return;
      if (d.amount !== undefined) r.amount = Number(d.amount);
      if (d.dueDate) r.dueDate = d.dueDate;
    });
    this.rows = Array.from(map.values());
    this.draftValues = [];
  }

  refreshRelatedLists() {
        getRecordNotifyChange([{ recordId: this.recordId }]);
        this.dispatchEvent(new RefreshEvent());
    }

  async save() {
    try {
        if (this.hasDiff) {
            this.toast('Error','Total installment harus sama dengan Amount','error'); 
            return;
        }

        const rawRows = JSON.parse(JSON.stringify(this.rows));
        const payload = rawRows.map(({ number, amount, dueDate }) => ({
            num: Number(number),
            amount: Number(amount),
            dueDate 
        }));

        console.log('payload (plain):', JSON.stringify(payload));
        console.log('this.paymentChannelId:', this.paymentChannelId);

        await savePayments({
            oppId: this.recordId,
            items: payload,
            paymentChannelId: this.paymentChannelId,
            allocation: 'Tuition Fee',
            paymentStatus: 'Unpaid'
        });

        await advanceOppStage({ oppId: this.recordId });

        this.toast('Success','Payment Information berhasil dibuat','success');
        this.dispatchEvent(new CloseActionScreenEvent());
        setTimeout(() => {

          window.top.location.replace(`/lightning/r/Opportunity/${this.recordId}/view`);
        }, 250);
        
    } catch (err) {
        this.toast('Error', (err?.body?.message || err?.message || 'Unknown error'), 'error');
    }
  }
  
makeRow(label, number, amount, dueDate) {
    return { id: `${number}`, label, number, amount, dueDate };
    }
  datePlusMonthsOn28(n) {
    const d = new Date();
    const dt = new Date(d.getFullYear(), d.getMonth() + n, 28);

    return dt.toISOString().slice(0,10); 
  }
  close(){ this.dispatchEvent(new CloseActionScreenEvent()); }
  toast(title, message, variant){ this.dispatchEvent(new ShowToastEvent({ title, message, variant })); }
}
