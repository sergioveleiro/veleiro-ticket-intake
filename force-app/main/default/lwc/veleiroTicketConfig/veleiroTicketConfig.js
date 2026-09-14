import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { MASCOT } from 'c/veleiroBrand';
import getSetup from '@salesforce/apex/VeleiroTicketController.getSetup';
import saveToken from '@salesforce/apex/VeleiroTicketController.saveToken';
import saveEnvironment from '@salesforce/apex/VeleiroTicketController.saveEnvironment';
import listClients from '@salesforce/apex/VeleiroTicketController.listClients';
import listProjects from '@salesforce/apex/VeleiroTicketController.listProjects';
import saveMapping from '@salesforce/apex/VeleiroTicketController.saveMapping';

const ENV_OPTIONS = [
    { label: 'Production (app.veleiro.ai)', value: 'Production' },
    { label: 'Beta (app.beta.veleiro.dev)', value: 'Beta' }
];

export default class VeleiroTicketConfig extends LightningElement {
    setup;

    // Connection
    token = '';
    environment = 'Production';
    editingConnection = false;
    savingConnection = false;
    envOptions = ENV_OPTIONS;

    // Mapping
    @track clientOptions = [];
    @track projectOptions = [];
    selectedClient = '';
    selectedClientName = '';
    selectedProject = '';
    selectedProjectName = '';
    loading = false;

    get mascot() {
        return MASCOT;
    }

    connectedCallback() {
        this.refresh();
    }

    refresh() {
        getSetup()
            .then((s) => {
                this.setup = s;
                this.environment = s.environment && s.environment !== 'Custom' ? s.environment : 'Production';
                this.editingConnection = !s.connected;
                this.selectedClient = s.clientId || '';
                this.selectedClientName = s.clientName || '';
                this.selectedProject = s.projectId || '';
                this.selectedProjectName = s.projectName || '';
                if (s.connected) this.loadClients();
            })
            .catch((e) => this.toastErr(e));
    }

    // ---------- Connection ----------
    get showConnectionForm() {
        return !this.setup || !this.setup.connected || this.editingConnection;
    }
    get canCancelConnection() {
        return this.setup && this.setup.connected;
    }
    get connectionSummary() {
        if (!this.setup) return '';
        let s = 'Connected · ' + (this.setup.environment || 'Production');
        if (this.setup.tokenMasked) s += ' · token ' + this.setup.tokenMasked;
        return s;
    }
    get tokenPlaceholder() {
        return this.setup && this.setup.connected ? 'Leave blank to keep the current token' : 'Paste your Veleiro API token (vlr_…)';
    }

    handleToken(e) {
        this.token = e.target.value;
    }
    handleEnv(e) {
        this.environment = e.detail.value;
    }

    saveConnection() {
        if ((!this.setup || !this.setup.connected) && !(this.token && this.token.trim())) {
            this.toast('Token required', 'Paste your Veleiro API token to connect.', 'warning');
            return;
        }
        this.savingConnection = true;
        const tokenToSave = this.token && this.token.trim() ? this.token : null;
        saveEnvironment({ environment: this.environment })
            .then(() => (tokenToSave ? saveToken({ token: tokenToSave }) : Promise.resolve()))
            .then(() => {
                this.token = '';
                this.editingConnection = false;
                this.toast('Connection saved', 'Veleiro connection updated.', 'success');
                this.refresh();
            })
            .catch((e) => this.toastErr(e))
            .finally(() => {
                this.savingConnection = false;
            });
    }

    editConnection() {
        this.editingConnection = true;
        this.token = '';
    }
    cancelConnection() {
        this.editingConnection = false;
        this.token = '';
    }

    // ---------- Mapping ----------
    get showMapping() {
        return this.setup && this.setup.connected && !this.editingConnection;
    }
    get canSave() {
        return !!this.selectedClient;
    }

    loadClients() {
        this.loading = true;
        listClients()
            .then((rows) => {
                this.clientOptions = rows.map((r) => ({ label: r.name, value: r.id }));
                if (this.selectedClient) this.loadProjects();
            })
            .catch((e) => this.toastErr(e))
            .finally(() => {
                this.loading = false;
            });
    }

    loadProjects() {
        if (!this.selectedClient) {
            this.projectOptions = [];
            return;
        }
        listProjects({ clientId: this.selectedClient })
            .then((rows) => {
                this.projectOptions = [{ label: '— None (client level) —', value: '' }].concat(
                    rows.map((r) => ({ label: r.name, value: r.id }))
                );
            })
            .catch((e) => this.toastErr(e));
    }

    handleClient(e) {
        this.selectedClient = e.detail.value;
        const opt = this.clientOptions.find((o) => o.value === this.selectedClient);
        this.selectedClientName = opt ? opt.label : '';
        this.selectedProject = '';
        this.selectedProjectName = '';
        this.loadProjects();
    }

    handleProject(e) {
        this.selectedProject = e.detail.value;
        const opt = this.projectOptions.find((o) => o.value === this.selectedProject);
        this.selectedProjectName = opt ? opt.label : '';
    }

    save() {
        saveMapping({
            clientId: this.selectedClient,
            clientName: this.selectedClientName,
            projectId: this.selectedProject,
            projectName: this.selectedProjectName
        })
            .then(() => {
                this.toast('Saved', 'Ticket destination updated.', 'success');
                this.refresh();
            })
            .catch((e) => this.toastErr(e));
    }

    // ---------- helpers ----------
    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
    toastErr(e) {
        this.toast('Error', (e && e.body && e.body.message) || 'Unexpected error', 'error');
    }
}
