/**
 * El detalle del ticket, en dos tarjetas: lo que el cliente puede cambiar y de donde salio.
 *
 * Es un LWC y no secciones de campo del flexipage por dos razones: las etiquetas de seccion de
 * un flexipage son texto plano (no siguen el idioma del usuario), y lightning-record-form toma
 * las etiquetas de cada campo del metadata, que Salesforce ya traduce a los tres idiomas.
 */
import { LightningElement, api } from 'lwc';
import { T } from 'c/veleiroTicketI18n';

import OBJ from '@salesforce/schema/Veleiro_Ticket__c';
import TITLE from '@salesforce/schema/Veleiro_Ticket__c.Title__c';
import DESCRIPTION from '@salesforce/schema/Veleiro_Ticket__c.Description__c';
import TYPE from '@salesforce/schema/Veleiro_Ticket__c.Ticket_Type__c';
import PRIORITY from '@salesforce/schema/Veleiro_Ticket__c.Priority__c';
import DUE_DATE from '@salesforce/schema/Veleiro_Ticket__c.Due_Date__c';
import STAGE from '@salesforce/schema/Veleiro_Ticket__c.Work_Status__c';
import ATTACHMENT_NOTE from '@salesforce/schema/Veleiro_Ticket__c.Attachment_Note__c';
import SF_RECORD from '@salesforce/schema/Veleiro_Ticket__c.SF_Record_Name__c';
import SF_OBJECT from '@salesforce/schema/Veleiro_Ticket__c.SF_Object__c';
import SOURCE_URL from '@salesforce/schema/Veleiro_Ticket__c.Source_URL__c';
import SUBMITTED_BY from '@salesforce/schema/Veleiro_Ticket__c.Submitted_By_Name__c';
import SUBMITTED_EMAIL from '@salesforce/schema/Veleiro_Ticket__c.Submitted_By_Email__c';
import LAST_SYNC from '@salesforce/schema/Veleiro_Ticket__c.Last_Sync__c';

export default class VeleiroTicketDetail extends LightningElement {
    @api recordId;
    labels = T;
    objectApiName = OBJ;

    // Lo que el cliente puede mover: contenido del ticket y la etapa (aprobar un UAT, cerrar).
    editable = [TITLE, DESCRIPTION, TYPE, PRIORITY, DUE_DATE, STAGE, ATTACHMENT_NOTE];
    // De donde vino el ticket. Solo lectura: lo escribe el alta, no la persona.
    origin = [SF_OBJECT, SF_RECORD, SOURCE_URL, SUBMITTED_BY, SUBMITTED_EMAIL, LAST_SYNC];
}
