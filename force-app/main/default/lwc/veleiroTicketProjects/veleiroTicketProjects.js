/**
 * Donde el partner decide que proyectos de Veleiro existen para este cliente.
 *
 * Primero los crea en Veleiro; aqui solo elige cuales habilita y si el cliente puede
 * levantar tickets en ellos o solo mirarlos. Apagar uno no borra nada: los tickets ya
 * bajados siguen visibles.
 *
 * Vive dentro del paso 3 del setup y le avisa con 'projectschanged' cuando el conteo cambia,
 * para que ese paso se ponga verde sin que nadie recargue la pagina.
 */
import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { T, fmt } from 'c/veleiroTicketI18n';
import listVeleiroProjects from '@salesforce/apex/VeleiroTicketController.listVeleiroProjects';
import saveEnabledProjects from '@salesforce/apex/VeleiroTicketController.saveEnabledProjects';

export default class VeleiroTicketProjects extends LightningElement {
    labels = T;
    rows = [];
    query = '';
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
            this.error = this.messageOf(e, this.labels.couldNotRead);
        } finally {
            this.loading = false;
        }
    }

    handleQuery(event) {
        this.query = event.target.value || '';
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
            this.toast(this.labels.saved, fmt(this.labels.savedProjects, [this.enabledCount]), 'success');
            await this.load();
            this.dispatchEvent(new CustomEvent('projectschanged'));
        } catch (e) {
            this.toast(this.labels.couldNotSave, this.messageOf(e, ''), 'error');
        } finally {
            this.saving = false;
        }
    }

    // Una lista de proyectos crece; filtrar escribiendo evita tener que hacer scroll.
    get visibleRows() {
        const q = this.query.trim().toLowerCase();
        return q ? this.rows.filter((r) => (r.name || '').toLowerCase().includes(q)) : this.rows;
    }

    get enabledCount() {
        return this.rows.filter((r) => r.enabled).length;
    }

    get countLabel() {
        return fmt(this.labels.enabledCount, [this.enabledCount, this.rows.length]);
    }

    get hasRows() {
        return this.rows.length > 0;
    }

    get showFilter() {
        return this.rows.length > 6;
    }

    get nothingMatches() {
        return this.hasRows && this.visibleRows.length === 0;
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
