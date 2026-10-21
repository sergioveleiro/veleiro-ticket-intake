/**
 * Donde el partner decide que proyectos de Veleiro existen para este cliente.
 *
 * Primero los crea en Veleiro; aqui solo elige cuales habilita y si el cliente puede
 * levantar tickets en ellos o solo mirarlos. Apagar uno no borra nada: los tickets ya
 * bajados siguen visibles.
 */
import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import listVeleiroProjects from '@salesforce/apex/VeleiroTicketController.listVeleiroProjects';
import saveEnabledProjects from '@salesforce/apex/VeleiroTicketController.saveEnabledProjects';
import pullNow from '@salesforce/apex/VeleiroTicketController.pullNow';

export default class VeleiroTicketProjects extends LightningElement {
    rows = [];
    loading = false;
    saving = false;
    error;

    connectedCallback() {
        this.load();
    }

    async load() {
        this.loading = true;
        this.error = undefined;
        try {
            const data = await listVeleiroProjects();
            this.rows = (data || []).map((p) => ({ ...p }));
        } catch (e) {
            this.error = this.messageOf(e, 'No pudimos leer los proyectos de Veleiro.');
        } finally {
            this.loading = false;
        }
    }

    handleToggle(event) {
        const id = event.target.dataset.id;
        const field = event.target.dataset.field;
        const checked = event.target.checked;
        this.rows = this.rows.map((r) => (r.projectId === id ? { ...r, [field]: checked } : r));
    }

    async handleSave() {
        this.saving = true;
        try {
            await saveEnabledProjects({ projectsJson: JSON.stringify(this.rows) });
            this.toast('Proyectos guardados', `${this.enabledCount} habilitados para este cliente.`, 'success');
            await this.load();
        } catch (e) {
            this.toast('No se pudo guardar', this.messageOf(e, ''), 'error');
        } finally {
            this.saving = false;
        }
    }

    // Traer ahora, sin esperar a que suene el reloj de cada hora.
    async handlePull() {
        this.saving = true;
        try {
            const r = await pullNow();
            if (r.error) {
                this.toast(`${r.pulled} tickets traídos`, r.error, 'warning');
            } else {
                this.toast('Al día', `${r.pulled} tickets desde ${r.projects} proyecto(s).`, 'success');
            }
        } catch (e) {
            this.toast('No se pudo traer', this.messageOf(e, ''), 'error');
        } finally {
            this.saving = false;
        }
    }

    get enabledCount() {
        return this.rows.filter((r) => r.enabled).length;
    }

    get hasRows() {
        return this.rows.length > 0;
    }

    get emptyMessage() {
        return 'No hay proyectos en Veleiro para este cliente todavía. Créalos allá y vuelve aquí para habilitarlos.';
    }

    get busy() {
        return this.loading || this.saving;
    }

    messageOf(e, fallback) {
        return (e && e.body && e.body.message) || (e && e.message) || fallback;
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
