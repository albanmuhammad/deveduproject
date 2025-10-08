import { LightningElement, api, wire } from 'lwc';
import { loadScript } from 'lightning/platformResourceLoader';
import QrLib from '@salesforce/resourceUrl/qrcode';
import { getRecord, getFieldValue, getFieldDisplayValue } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import savePng from '@salesforce/apex/QrFileController.savePng';

// === Account fields (tanpa Job & Address) ===
import NAME            from '@salesforce/schema/Account.Name';
import ACCOUNT_NUMBER  from '@salesforce/schema/Account.AccountNumber';
import PHONE           from '@salesforce/schema/Account.Phone';
import PERSON_MOBILE   from '@salesforce/schema/Account.PersonMobilePhone';
import PERSON_EMAIL    from '@salesforce/schema/Account.PersonEmail';
import PERSON_BIRTHDT  from '@salesforce/schema/Account.PersonBirthdate';
import RATING          from '@salesforce/schema/Account.Rating';

// Lookup Master School → ambil display name (Name)
import SCHOOL          from '@salesforce/schema/Account.Master_School__c';

const FIELDS = [
  NAME, ACCOUNT_NUMBER, PHONE, PERSON_MOBILE,
  PERSON_EMAIL, PERSON_BIRTHDT, RATING, SCHOOL
];

export default class QrAccountCard extends LightningElement {
  @api recordId;

  qrLoaded = false;
  qrContainer;
  qrPreviewText = '';   // teks multi-baris yang akan di-encode

  @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
  wiredAcc({ data, error }) {
    if (data) {
      const name       = getFieldValue(data, NAME);
      const accNo      = getFieldValue(data, ACCOUNT_NUMBER);
      const email      = getFieldValue(data, PERSON_EMAIL);
      const phone      = getFieldValue(data, PHONE) || getFieldValue(data, PERSON_MOBILE);
      const birthdate  = getFieldValue(data, PERSON_BIRTHDT);     // YYYY-MM-DD
      const rating     = getFieldValue(data, RATING);
      const schoolName = getFieldDisplayValue(data, SCHOOL) || ''; // Name dari lookup

      this.qrPreviewText = this.formatForHuman({
        name, applicantNumber: accNo, school: schoolName, email, phone, birthdate, rating
      });
      this.renderQr();
    } else if (error) {
      // eslint-disable-next-line no-console
      console.error('getRecord error', JSON.stringify(error));
      this.toast('Gagal memuat data', this.messageFromError(error), 'error');
    }
  }

  // Susun teks multi-baris; field kosong otomatis tidak ditampilkan
  formatForHuman({ name, applicantNumber, school, email, phone, birthdate, rating }) {
    const lines = [];
    const push = (label, val) => { if (val) lines.push(`${label}: ${val}`); };

    push('Applicant', name);
    push('Applicant No', applicantNumber);
    push('School', school);
    push('Email', email);
    push('Phone', phone);
    push('Birthdate', birthdate);
    push('Rating', rating);

    return lines.join('\n');
  }

  renderedCallback() {
    if (!this.qrLoaded) {
      this.qrLoaded = true;
      loadScript(this, QrLib)
        .then(() => this.renderQr())
        .catch((e) => {
          // eslint-disable-next-line no-console
          console.error('Load QR lib error', e);
          this.toast('Gagal memuat library QR', e?.message || '', 'error');
        });
    }
    if (!this.qrContainer) {
      this.qrContainer = this.template.querySelector('.qr');
    }
  }

  renderQr = () => {
    if (!this.qrContainer || !this.qrPreviewText || !window.QRCode) return;
    this.qrContainer.innerHTML = '';
    // eslint-disable-next-line no-undef
    new QRCode(this.qrContainer, {
      text: this.qrPreviewText,
      width: 240,
      height: 240,
      correctLevel: QRCode.CorrectLevel.M
    });
  };

  async handleSave() {
    try {
      // Ambil <canvas> (atau fallback <img>)
      let canvas = this.qrContainer?.querySelector('canvas');
      if (!canvas) {
        const img = this.qrContainer?.querySelector('img');
        if (!img) { this.toast('QR belum siap', 'Canvas/IMG QR tidak ditemukan.', 'warning'); return; }
        const temp = document.createElement('canvas');
        temp.width = img.naturalWidth || 240;
        temp.height = img.naturalHeight || 240;
        const ctx = temp.getContext('2d');
        ctx.fillStyle = '#ffffff';
        ctx.fillRect(0, 0, temp.width, temp.height);
        ctx.drawImage(img, 0, 0);
        canvas = temp;
      }
      const dataUrl = canvas.toDataURL('image/png');
      const base64 = dataUrl.split(',')[1];
      await savePng({ parentId: this.recordId, base64Png: base64, fileName: `QR-Applicant-${this.recordId}.png` });
      this.toast('Berhasil', 'QR tersimpan ke Files.', 'success');
    } catch (e) {
      // eslint-disable-next-line no-console
      console.error('Save error', e);
      this.toast('Gagal menyimpan', this.messageFromError(e), 'error');
    }
  }

  toast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }
  messageFromError(e) {
    return e?.body?.message || e?.message || 'Unknown error';
  }
}