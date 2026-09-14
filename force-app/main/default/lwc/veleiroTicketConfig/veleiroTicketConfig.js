import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getSetup from '@salesforce/apex/VeleiroTicketController.getSetup';
import listClients from '@salesforce/apex/VeleiroTicketController.listClients';
import listProjects from '@salesforce/apex/VeleiroTicketController.listProjects';
import saveMapping from '@salesforce/apex/VeleiroTicketController.saveMapping';

export default class VeleiroTicketConfig extends LightningElement {
    setup;
    @track clientOptions = [];
    @track projectOptions = [];
    selectedClient = '';
    selectedClientName = '';
    selectedProject = '';
    selectedProjectName = '';
    loading = false;

    connectedCallback() {
        this.refresh();
    }

    refresh() {
        getSetup()
            .then((s) => {
                this.setup = s;
                this.selectedClient = s.clientId || '';
                this.selectedClientName = s.clientName || '';
                this.selectedProject = s.projectId || '';
                this.selectedProjectName = s.projectName || '';
                if (s.connected) this.loadClients();
            })
            .catch((e) => this.toastErr(e));
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
                this.dispatchEvent(
                    new ShowToastEvent({ title: 'Saved', message: 'Ticket destination updated.', variant: 'success' })
                );
                this.refresh();
            })
            .catch((e) => this.toastErr(e));
    }

    toastErr(e) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Error',
                message: (e && e.body && e.body.message) || 'Unexpected error',
                variant: 'error'
            })
        );
    }

    get notConnected() {
        return !this.setup || !this.setup.connected;
    }

    get canSave() {
        return !!this.selectedClient;
    }

    get environment() {
        return this.setup ? this.setup.environment : '';
    }
}
