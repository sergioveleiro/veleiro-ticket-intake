/**
 * El setup del paquete, en cuatro pasos y una sola superficie.
 *
 * Cada paso sabe si ya esta hecho mirando el estado real de la org (token puesto, cliente
 * guardado, proyectos habilitados, reloj programado), no una bandera que alguien marco. Un
 * paso hecho se colapsa a su resumen; el siguiente pendiente es el que esta abierto.
 *
 * El selector de clientes filtra escribiendo: un partner con cien clientes no puede depender
 * de un dropdown sin busqueda.
 */
import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { MASCOT } from 'c/veleiroTicketBrand';
import { T, fmt } from 'c/veleiroTicketI18n';
import getSetup from '@salesforce/apex/VeleiroTicketController.getSetup';
import saveToken from '@salesforce/apex/VeleiroTicketController.saveToken';
import saveEnvironment from '@salesforce/apex/VeleiroTicketController.saveEnvironment';
import listClients from '@salesforce/apex/VeleiroTicketController.listClients';
import saveMapping from '@salesforce/apex/VeleiroTicketController.saveMapping';
import schedulePull from '@salesforce/apex/VeleiroTicketController.schedulePull';
import pullNow from '@salesforce/apex/VeleiroTicketController.pullNow';

const MAX_CLIENT_ROWS = 8;

export default class VeleiroTicketConfig extends LightningElement {
    labels = T;
    mascot = MASCOT;
    setup;

    // Paso 1
    token = '';
    environment = 'Production';
    savingConnection = false;

    // Paso 2
    @track clients = [];
    clientQuery = '';
    pickedClientId = '';
    pickedClientName = '';
    loadingClients = false;
    savingClient = false;

    // Paso 4
    frequency = 'hourly';
    savingSchedule = false;
    pulling = false;

    // Que paso esta abierto. null = el primero pendiente.
    openStep = null;

    connectedCallback() {
        this.refresh();
    }

    refresh() {
        return getSetup()
            .then((s) => {
                this.setup = s;
                this.environment = s.environment && s.environment !== 'Custom' ? s.environment : 'Production';
                this.pickedClientId = s.clientId || '';
                this.pickedClientName = s.clientName || '';
                this.frequency = s.pullFrequency || 'off';
                if (s.connected && !this.clients.length) this.loadClients();
            })
            .catch((e) => this.toastErr(e));
    }

    // ---------- estado de los pasos ----------
    get connected() { return !!(this.setup && this.setup.connected); }
    get hasClient() { return !!(this.setup && this.setup.clientId); }
    get hasProjects() { return !!(this.setup && this.setup.enabledProjects > 0); }
    get scheduled() { return !!(this.setup && this.setup.pullFrequency && this.setup.pullFrequency !== 'off'); }

    get steps() {
        const done = [this.connected, this.hasClient, this.hasProjects, this.scheduled];
        const open = this.openStep || done.findIndex((d) => !d) + 1 || 1;
        return [1, 2, 3, 4].map((n) => ({
            n,
            done: done[n - 1],
            open: n === open,
            locked: (n >= 2 && !this.connected) || (n >= 3 && !this.hasClient)
        }));
    }

    stepAt(n) { return this.steps[n - 1]; }

    get step1() { return this.stepAt(1); }
    get step2() { return this.stepAt(2); }
    get step3() { return this.stepAt(3); }
    get step4() { return this.stepAt(4); }

    // Cada paso pide tres cosas al template: si se ve el cuerpo, su clase y el resumen.
    get show1() { return this.step1.open; }
    get show2() { return this.step2.open && !this.step2.locked; }
    get show3() { return this.step3.open && !this.step3.locked; }
    get show4() { return this.step4.open && !this.step4.locked; }

    get class1() { return this.stepClass(this.step1); }
    get class2() { return this.stepClass(this.step2); }
    get class3() { return this.stepClass(this.step3); }
    get class4() { return this.stepClass(this.step4); }

    stepClass(st) {
        return 'vts-step' + (st.done ? ' vts-done' : '') + (st.open ? ' vts-open' : '') +
               (st.locked ? ' vts-locked' : '');
    }

    get summary1() {
        if (!this.connected) return this.labels.notConnected;
        let out = (this.setup.environment || 'Production');
        if (this.setup.tokenMasked) out += ' · ' + this.setup.tokenMasked;
        return out;
    }
    get summary2() { return this.setup && this.setup.clientName ? this.setup.clientName : ''; }
    get summary3() {
        const n = (this.setup && this.setup.enabledProjects) || 0;
        return n ? fmt(this.labels.projectsEnabled, [n]) : this.labels.noneEnabled;
    }
    get summary4() {
        if (!this.scheduled) return this.labels.freqOff;
        const name = this.setup.pullFrequency === 'daily' ? this.labels.freqDaily : this.labels.freqHourly;
        return this.setup.pullNextRun
            ? name + ' · ' + this.labels.nextRun + ': ' + new Date(this.setup.pullNextRun).toLocaleString()
            : name;
    }

    handleStepClick(event) {
        const n = parseInt(event.currentTarget.dataset.step, 10);
        const st = this.stepAt(n);
        if (st.locked) return;
        this.openStep = st.open ? null : n;
    }

    // ---------- paso 1: conexion ----------
    get envOptions() {
        return [
            { label: 'Production · app.veleiro.ai', value: 'Production' },
            { label: 'Beta · app.beta.veleiro.dev', value: 'Beta' }
        ];
    }
    get tokenPlaceholder() {
        return this.connected ? '•••• ' + this.labels.change : this.labels.tokenPlaceholder;
    }

    handleToken(e) { this.token = e.target.value; }
    handleEnv(e) { this.environment = e.detail.value; }

    saveConnection() {
        if (!this.connected && !(this.token || '').trim()) {
            this.toast(this.labels.token, this.labels.tokenPlaceholder, 'warning');
            return;
        }
        const tokenToSave = (this.token || '').trim() || null;
        this.savingConnection = true;
        saveEnvironment({ environment: this.environment })
            .then(() => (tokenToSave ? saveToken({ token: tokenToSave }) : null))
            .then(() => {
                this.token = '';
                this.openStep = null;
                this.clients = [];
                this.toast(this.labels.saved, this.labels.connected, 'success');
                return this.refresh();
            })
            .catch((e) => this.toastErr(e))
            .finally(() => { this.savingConnection = false; });
    }

    // ---------- paso 2: cliente ----------
    loadClients() {
        this.loadingClients = true;
        listClients()
            .then((rows) => { this.clients = (rows || []).map((r) => ({ id: r.id, name: r.name })); })
            .catch((e) => this.toastErr(e))
            .finally(() => { this.loadingClients = false; });
    }

    handleClientQuery(e) { this.clientQuery = e.target.value || ''; }

    get clientRows() {
        const q = this.clientQuery.trim().toLowerCase();
        const matches = q ? this.clients.filter((c) => c.name.toLowerCase().includes(q)) : this.clients;
        return matches.slice(0, MAX_CLIENT_ROWS).map((c) => ({
            ...c,
            cls: 'vts-client' + (c.id === this.pickedClientId ? ' vts-client-on' : '')
        }));
    }
    get moreClients() {
        const q = this.clientQuery.trim().toLowerCase();
        const total = q ? this.clients.filter((c) => c.name.toLowerCase().includes(q)).length : this.clients.length;
        return total > MAX_CLIENT_ROWS ? total - MAX_CLIENT_ROWS : 0;
    }
    get hasMoreClients() { return this.moreClients > 0; }
    get noClientMatches() { return !this.loadingClients && this.clients.length > 0 && this.clientRows.length === 0; }

    handlePickClient(e) {
        this.pickedClientId = e.currentTarget.dataset.id;
        this.pickedClientName = e.currentTarget.dataset.name;
    }

    get canSaveClient() { return !!this.pickedClientId && !this.savingClient; }

    saveClient() {
        this.savingClient = true;
        // El proyecto por defecto ya no se elige aqui: cada ticket lleva el suyo (paso 3).
        saveMapping({
            clientId: this.pickedClientId,
            clientName: this.pickedClientName,
            projectId: null,
            projectName: null
        })
            .then(() => {
                this.openStep = null;
                this.toast(this.labels.saved, this.pickedClientName, 'success');
                return this.refresh();
            })
            .catch((e) => this.toastErr(e))
            .finally(() => { this.savingClient = false; });
    }

    // ---------- paso 3: proyectos ----------
    // El componente de proyectos avisa cuando cambia el conteo para que el paso se ponga verde.
    handleProjectsChanged() {
        this.refresh();
    }

    // ---------- paso 4: reloj ----------
    get freqOptions() {
        return [
            { label: this.labels.freqHourly, value: 'hourly' },
            { label: this.labels.freqDaily, value: 'daily' },
            { label: this.labels.freqOff, value: 'off' }
        ];
    }

    handleFrequency(e) { this.frequency = e.detail.value; }

    saveSchedule() {
        this.savingSchedule = true;
        schedulePull({ frequency: this.frequency })
            .then(() => {
                this.toast(this.labels.scheduleSaved, '', 'success');
                return this.refresh();
            })
            .catch((e) => this.toastErr(e))
            .finally(() => { this.savingSchedule = false; });
    }

    handlePullNow() {
        this.pulling = true;
        pullNow()
            .then((r) => {
                if (r && r.error) this.toast(this.labels.couldNotPull, r.error, 'warning');
                else this.toast(this.labels.upToDate, fmt(this.labels.pulled, [r.pulled, r.projects]), 'success');
            })
            .catch((e) => this.toast(this.labels.couldNotPull, this.messageOf(e), 'error'))
            .finally(() => { this.pulling = false; });
    }

    get busy4() { return this.savingSchedule || this.pulling; }

    // ---------- helpers ----------
    messageOf(e) {
        return (e && e.body && e.body.message) || (e && e.message) || '';
    }
    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
    toastErr(e) {
        this.toast(this.labels.couldNotSave, this.messageOf(e), 'error');
    }
}
