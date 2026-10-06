import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import retryPush from '@salesforce/apex/VeleiroTicketController.retryPush';

// Accion de registro: reenvia a Veleiro un ticket que quedo en Error, sin crear otro.
export default class VeleiroTicketRetry extends LightningElement {
    @api recordId;

    @api async invoke() {
        try {
            await retryPush({ ticketId: this.recordId });
            this.toast('Sending to Veleiro', 'The ticket was queued again. Refresh in a moment.', 'success');
        } catch (e) {
            const msg = e && e.body && e.body.message ? e.body.message : 'Could not resend the ticket';
            this.toast('Veleiro error', msg, 'error');
        }
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
