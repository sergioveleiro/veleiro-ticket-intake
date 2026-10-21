/**
 * El ticket visto desde Veleiro, en su propia pagina de Salesforce.
 *
 * Los campos se importan por schema (@salesforce/schema/...) y no por nombre de texto: asi
 * el prefijo del namespace lo resuelve Salesforce y no nosotros. Es la misma trampa que ya
 * nos mordio tres veces en el kit de ventas.
 */
import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { T } from 'c/veleiroTicketI18n';
import boardUrlFor from '@salesforce/apex/VeleiroTicketController.boardUrl';
import { MASCOT } from 'c/veleiroTicketBrand';

import TASK_KEY from '@salesforce/schema/Veleiro_Ticket__c.Veleiro_Task_Key__c';
import TASK_URL from '@salesforce/schema/Veleiro_Ticket__c.Veleiro_Task_Url__c';
import STATUS from '@salesforce/schema/Veleiro_Ticket__c.Veleiro_Status__c';
import STAGE from '@salesforce/schema/Veleiro_Ticket__c.Work_Status__c';
import PRIORITY from '@salesforce/schema/Veleiro_Ticket__c.Priority__c';
import PROJECT from '@salesforce/schema/Veleiro_Ticket__c.Veleiro_Project_Name__c';
import PROJECT_ID from '@salesforce/schema/Veleiro_Ticket__c.Veleiro_Project_Id__c';
import ASSIGNEES from '@salesforce/schema/Veleiro_Ticket__c.Assignees__c';
import LABELS from '@salesforce/schema/Veleiro_Ticket__c.Labels__c';
import FILES from '@salesforce/schema/Veleiro_Ticket__c.Attachment_Count__c';
import UPDATED from '@salesforce/schema/Veleiro_Ticket__c.Veleiro_Updated_At__c';
import ARCHIVED from '@salesforce/schema/Veleiro_Ticket__c.Is_Archived__c';
import SYNC_ERROR from '@salesforce/schema/Veleiro_Ticket__c.Sync_Error__c';

const FIELDS = [TASK_KEY, TASK_URL, STATUS, STAGE, PRIORITY, PROJECT, PROJECT_ID, ASSIGNEES,
                LABELS, FILES, UPDATED, ARCHIVED, SYNC_ERROR];

// El color de la barra sale del tipo de estado, que es lo unico estable entre partners.
const STAGE_TONE = {
    initial: 'new',
    in_progress: 'progress',
    blocked: 'blocked',
    review: 'review',
    terminal: 'done'
};

export default class VeleiroTicketPanel extends LightningElement {
    @api recordId;
    labels = T;
    mascotUrl = MASCOT;
    record;
    boardUrl;

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wired(result) {
        if (!result.data) return;
        this.record = result.data;
        const projectId = getFieldValue(result.data, PROJECT_ID);
        if (projectId && !this.boardUrl) {
            boardUrlFor({ veleiroProjectId: projectId })
                .then((u) => { this.boardUrl = u; })
                .catch(() => { /* sin tablero el panel sigue sirviendo */ });
        }
    }

    val(field) {
        return this.record ? getFieldValue(this.record, field) : undefined;
    }

    get taskKey() { return this.val(TASK_KEY); }
    get taskUrl() { return this.val(TASK_URL); }
    get status() { return this.val(STATUS); }
    get priority() { return this.val(PRIORITY); }
    get project() { return this.val(PROJECT); }
    get assignees() { return this.val(ASSIGNEES); }
    get labelsText() { return this.val(LABELS); }
    get fileCount() { return this.val(FILES); }
    get updated() { return this.val(UPDATED); }
    get archived() { return this.val(ARCHIVED) === true; }
    get syncError() { return this.val(SYNC_ERROR); }

    get stageClass() {
        return 'vtp-stage vtp-stage-' + (STAGE_TONE[this.val(STAGE)] || 'new');
    }

    // Sin vinculo todavia no hay nada que abrir: el ticket aun no llego a Veleiro.
    get hasLink() { return !!this.taskUrl; }
    get hasAssignees() { return !!this.assignees; }
    get hasLabels() { return !!this.labelsText; }
    get hasFiles() { return this.fileCount > 0; }
    get hasError() { return !!this.syncError; }
    get hasBoard() { return !!this.boardUrl; }

    get chips() {
        return (this.labelsText || '').split(',').map((s) => s.trim()).filter(Boolean)
            .map((name, i) => ({ key: name + i, name }));
    }
}
