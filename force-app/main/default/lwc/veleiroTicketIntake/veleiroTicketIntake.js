import { LightningElement, wire, track } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { MASCOT } from 'c/veleiroBrand';
import getSetup from '@salesforce/apex/VeleiroTicketController.getSetup';
import createTicket from '@salesforce/apex/VeleiroTicketController.createTicket';

// Etiquetas amigables para el usuario final. VeleiroTicketService normaliza cada valor
// al que ACEPTA el API de Veleiro (task/story/… y low/medium/high/critical) antes de enviar.
const TYPE_OPTIONS = [
    { label: 'Task', value: 'Task' },
    { label: 'Bug', value: 'Bug' },
    { label: 'Question', value: 'Question' },
    { label: 'Feature', value: 'Feature' },
    { label: 'Other', value: 'Other' }
];
const PRIORITY_OPTIONS = [
    { label: 'Low', value: 'Low' },
    { label: 'Medium', value: 'Medium' },
    { label: 'High', value: 'High' },
    { label: 'Urgent', value: 'Urgent' }
];

export default class VeleiroTicketIntake extends LightningElement {
    @track title = '';
    @track description = '';
    type = 'Task';
    priority = 'Medium';
    dueDate = '';
    sourceUrl = '';
    sfRecordId = '';
    sfObject = '';
    @track files = []; // { name, base64, contentType }

    setup;
    submitting = false;

    typeOptions = TYPE_OPTIONS;
    priorityOptions = PRIORITY_OPTIONS;
    dragOver = false;

    get mascot() {
        return MASCOT;
    }

    get dropzoneClass() {
        return this.dragOver ? 'velly-dropzone velly-dropzone_over' : 'velly-dropzone';
    }

    // Cuando el componente vive en una record page, aqui llega el contexto de forma confiable.
    @wire(CurrentPageReference)
    setPageRef(ref) {
        if (ref && ref.attributes) {
            if (ref.attributes.recordId) this.sfRecordId = ref.attributes.recordId;
            if (ref.attributes.objectApiName) this.sfObject = ref.attributes.objectApiName;
        }
    }

    connectedCallback() {
        this.captureContext();
        getSetup()
            .then((s) => {
                this.setup = s;
            })
            .catch(() => {
                /* sin setup mostramos el form igual */
            });
    }

    // La URL del navegador es la fuente confiable de contexto en cualquier tipo de app
    // (console o standard) y desde la utility bar. Complementa a CurrentPageReference.
    captureContext() {
        try {
            const href = window.location.href;
            this.sourceUrl = href;
            const m = href.match(/\/lightning\/r\/([^/]+)\/([^/]+)\//);
            if (m) {
                if (!this.sfObject) this.sfObject = decodeURIComponent(m[1]);
                if (!this.sfRecordId) this.sfRecordId = m[2];
            }
        } catch (e) {
            /* noop */
        }
    }

    get destinationLabel() {
        if (!this.setup) return '';
        if (!this.setup.connected) {
            return 'Not connected to Veleiro yet — the ticket will be saved in Salesforce only.';
        }
        if (!this.setup.clientId) {
            return 'No Veleiro client mapped yet — set it in Ticket Intake Setup.';
        }
        let d = 'Goes to Veleiro: ' + (this.setup.clientName || this.setup.clientId);
        if (this.setup.projectName || this.setup.projectId) {
            d += ' / ' + (this.setup.projectName || this.setup.projectId);
        }
        return d;
    }

    get destinationClass() {
        if (this.setup && this.setup.connected && this.setup.clientId) {
            return 'velly-connected';
        }
        return 'velly-weak';
    }

    get hasContext() {
        return !!this.sourceUrl;
    }

    get canSubmit() {
        return !this.submitting && !!this.title && this.title.trim().length > 0;
    }

    get fileNames() {
        return this.files.map((f, i) => ({ key: i, name: f.name }));
    }

    handleField(e) {
        const f = e.target.dataset.field;
        this[f] = e.target.value;
    }

    handleFiles(e) {
        this.ingest(e.target.files);
    }

    triggerBrowse() {
        const input = this.template.querySelector('input[type="file"]');
        if (input) input.click();
    }

    onDragOver(e) {
        e.preventDefault();
        this.dragOver = true;
    }

    onDragLeave() {
        this.dragOver = false;
    }

    onDrop(e) {
        e.preventDefault();
        this.dragOver = false;
        this.ingest(e.dataTransfer && e.dataTransfer.files);
    }

    ingest(list) {
        if (!list || !list.length) return;
        const readers = [];
        for (const file of list) {
            readers.push(this.readFile(file));
        }
        Promise.all(readers).then((fs) => {
            this.files = this.files.concat(fs.filter(Boolean));
        });
    }

    handlePaste(e) {
        const items = (e.clipboardData && e.clipboardData.items) || [];
        for (const it of items) {
            if (it.kind === 'file') {
                const file = it.getAsFile();
                if (file) {
                    this.readFile(file).then((f) => {
                        if (f) this.files = this.files.concat([f]);
                    });
                }
            }
        }
    }

    readFile(file) {
        return new Promise((resolve) => {
            const r = new FileReader();
            r.onload = () => {
                const parts = String(r.result).split(',');
                resolve({
                    name: file.name || 'pasted.png',
                    base64: parts.length > 1 ? parts[1] : parts[0],
                    contentType: file.type || 'application/octet-stream'
                });
            };
            r.onerror = () => resolve(null);
            r.readAsDataURL(file);
        });
    }

    removeFile(e) {
        const idx = parseInt(e.target.dataset.idx, 10);
        this.files = this.files.filter((f, i) => i !== idx);
    }

    submit() {
        if (!this.canSubmit) return;
        this.submitting = true;
        const payload = {
            title: this.title,
            description: this.description,
            ticketType: this.type,
            priority: this.priority,
            dueDate: this.dueDate,
            sourceUrl: this.sourceUrl,
            sfRecordId: this.sfRecordId,
            sfObject: this.sfObject,
            files: this.files
        };
        createTicket({ payloadJson: JSON.stringify(payload) })
            .then(() => {
                const sending = this.setup && this.setup.connected && this.setup.clientId;
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Ticket raised',
                        message: sending
                            ? 'Your ticket was created and is being sent to Veleiro.'
                            : 'Your ticket was saved in Salesforce.',
                        variant: 'success'
                    })
                );
                this.reset();
            })
            .catch((err) => {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Could not raise the ticket',
                        message: (err && err.body && err.body.message) || 'Unexpected error',
                        variant: 'error'
                    })
                );
            })
            .finally(() => {
                this.submitting = false;
            });
    }

    reset() {
        this.title = '';
        this.description = '';
        this.type = 'Task';
        this.priority = 'Medium';
        this.dueDate = '';
        this.files = [];
        this.captureContext();
    }
}
