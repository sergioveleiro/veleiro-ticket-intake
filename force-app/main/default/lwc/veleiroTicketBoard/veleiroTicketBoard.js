/**
 * La vista avanzada: los tickets como tablero o como lista, con filtros que responden al tacto.
 *
 * Existe porque las list views de Salesforce no dan para esto dentro de un paquete: el Kanban
 * solo agrupa por picklists editables, su configuracion de columnas no es empaquetable, y una
 * list view que viaja en un paquete administrado le llega al cliente en solo lectura, asi que
 * no puede ni agregarle un filtro. Aqui el filtrado pasa en el navegador sobre los tickets que
 * ya estan cargados, que es lo que lo hace instantaneo.
 *
 * Arrastrar una tarjeta escribe en Veleiro primero y en Salesforce despues: si Veleiro dice no,
 * la tarjeta regresa a su columna y la persona se entera. Nunca se queda un cambio local que la
 * siguiente bajada borraria en silencio.
 */
import { LightningElement, wire, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import { T, fmt } from 'c/veleiroTicketI18n';
import { MASCOT } from 'c/veleiroTicketBrand';
import loadBoard from '@salesforce/apex/VeleiroTicketBoardController.load';
import moveTicket from '@salesforce/apex/VeleiroTicketBoardController.move';
import pullNow from '@salesforce/apex/VeleiroTicketController.pullNow';

const STAGE_LABEL = {
    initial: 'stInitial',
    in_progress: 'stInProgress',
    blocked: 'stBlocked',
    review: 'stReview',
    terminal: 'stTerminal'
};
const STAGE_TONE = {
    initial: 'new',
    in_progress: 'progress',
    blocked: 'blocked',
    review: 'review',
    terminal: 'done'
};
// Mensaje propio por cada razon por la que Veleiro puede negarse. Se ramifica por code.
const MOVE_MESSAGE = {
    not_allowed: 'mNotAllowed',
    no_such_stage: 'mNoStage',
    not_in_veleiro: 'mNotInVeleiro',
    version_conflict: 'mConflict'
};

export default class VeleiroTicketBoard extends NavigationMixin(LightningElement) {
    labels = T;
    mascot = MASCOT;

    board;
    wiredResult;
    error;

    view = 'board';
    @track query = '';
    project = '';
    priority = '';
    assignee = '';
    withArchived = false;
    groupField = '';

    dragId;
    dropStage;
    moving = false;
    pulling = false;

    @wire(loadBoard)
    wired(result) {
        this.wiredResult = result;
        if (result.data) {
            this.board = result.data;
            this.error = undefined;
        } else if (result.error) {
            this.error = (result.error.body && result.error.body.message) || 'Error';
        }
    }

    // ---------- cabecera ----------
    get boardView() { return this.view === 'board'; }
    get listView() { return this.view === 'list'; }
    get boardBtnClass() { return 'vtb-toggle' + (this.boardView ? ' vtb-toggle-on' : ''); }
    get listBtnClass() { return 'vtb-toggle' + (this.listView ? ' vtb-toggle-on' : ''); }
    handleView(event) { this.view = event.currentTarget.dataset.view; }

    get hasBoardUrl() { return !!(this.board && this.board.boardUrl); }
    get boardUrl() { return this.board && this.board.boardUrl; }

    get countLabel() {
        const all = (this.board && this.board.cards) || [];
        return fmt(this.labels.ticketCount, [this.visible.length, all.length]);
    }
    get truncatedLabel() {
        return this.board && this.board.truncated
            ? fmt(this.labels.truncated, [this.board.cards.length])
            : '';
    }
    get isTruncated() { return !!(this.board && this.board.truncated); }
    get busy() { return this.moving || this.pulling; }

    // ---------- filtros ----------
    get projectOptions() { return this.optionsFrom(this.board && this.board.projects, this.labels.allProjects); }
    get priorityOptions() { return this.optionsFrom(this.board && this.board.priorities, this.labels.allPriorities); }
    get assigneeOptions() { return this.optionsFrom(this.board && this.board.assignees, this.labels.allAssignees); }

    optionsFrom(values, anyLabel) {
        return [{ label: anyLabel, value: '' }].concat(
            (values || []).map((v) => ({ label: v, value: v }))
        );
    }

    get groupOptions() {
        return [
            { label: this.labels.groupNone, value: '' },
            { label: this.labels.colStage, value: 'stage' },
            { label: this.labels.colProject, value: 'project' },
            { label: this.labels.fPriority, value: 'priority' }
        ];
    }

    handleQuery(event) { this.query = event.target.value || ''; }
    handleProject(event) { this.project = event.detail.value; }
    handlePriority(event) { this.priority = event.detail.value; }
    handleAssignee(event) { this.assignee = event.detail.value; }
    handleArchived(event) { this.withArchived = event.target.checked; }
    handleGroup(event) { this.groupField = event.detail.value; }

    get hasFilters() {
        return !!(this.query || this.project || this.priority || this.assignee || this.withArchived);
    }

    clearFilters() {
        this.query = '';
        this.project = '';
        this.priority = '';
        this.assignee = '';
        this.withArchived = false;
    }

    // ---------- los datos que se ven ----------
    get visible() {
        const cards = (this.board && this.board.cards) || [];
        const q = this.query.trim().toLowerCase();
        return cards.filter((c) => {
            if (!this.withArchived && c.archived) return false;
            if (this.project && c.project !== this.project) return false;
            if (this.priority && c.priority !== this.priority) return false;
            if (this.assignee && !(c.assignees || '').includes(this.assignee)) return false;
            if (!q) return true;
            const hay = [c.name, c.key, c.title, c.statusName, (c.labels || []).join(' ')]
                .filter(Boolean).join(' ').toLowerCase();
            return hay.includes(q);
        });
    }

    get columns() {
        const stages = (this.board && this.board.stages) || [];
        const visible = this.visible;
        return stages.map((stage) => {
            const cards = visible.filter((c) => c.stage === stage).map((c) => this.decorate(c));
            return {
                stage,
                label: this.labels[STAGE_LABEL[stage]] || stage,
                tone: STAGE_TONE[stage] || 'new',
                count: cards.length,
                cards,
                empty: cards.length === 0,
                cls: 'vtb-col vtb-col-' + (STAGE_TONE[stage] || 'new') +
                     (this.dropStage === stage ? ' vtb-col-over' : '')
            };
        });
    }

    get groups() {
        const visible = this.visible.map((c) => this.decorate(c));
        if (!this.groupField) {
            return [{ key: 'all', label: '', rows: visible, showHeader: false }];
        }
        const buckets = new Map();
        visible.forEach((c) => {
            const raw = c[this.groupField];
            const label = this.groupField === 'stage'
                ? (this.labels[STAGE_LABEL[raw]] || raw)
                : (raw || '—');
            if (!buckets.has(label)) buckets.set(label, []);
            buckets.get(label).push(c);
        });
        return [...buckets.entries()]
            .sort((a, b) => a[0].localeCompare(b[0]))
            .map(([label, rows]) => ({ key: label, label, rows, showHeader: true, count: rows.length }));
    }

    get nothingVisible() { return this.visible.length === 0 && !this.error; }

    // Lo que el template no puede calcular: clases, etiquetas y banderas por tarjeta.
    decorate(c) {
        return {
            ...c,
            stageLabel: this.labels[STAGE_LABEL[c.stage]] || c.stage,
            stageCls: 'vtb-pill vtb-pill-' + (STAGE_TONE[c.stage] || 'new'),
            cardCls: 'vtb-card' + (c.archived ? ' vtb-card-archived' : '') +
                     (this.dragId === c.recordId ? ' vtb-card-dragging' : ''),
            prioCls: 'vtb-prio vtb-prio-' + (c.priority || 'none').toLowerCase(),
            hasLabels: (c.labels || []).length > 0,
            chips: (c.labels || []).map((n, i) => ({ key: n + i, name: n })),
            hasAssignees: !!c.assignees,
            hasDue: !!c.dueDate,
            hasFiles: c.files > 0,
            hasError: !!c.syncError,
            statusOrStage: c.statusName || (this.labels[STAGE_LABEL[c.stage]] || c.stage)
        };
    }

    // ---------- navegar ----------
    handleOpen(event) {
        const recordId = event.currentTarget.dataset.id;
        if (!recordId) return;
        this.navigateTo(recordId);
    }

    handleOpenKey(event) {
        if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            this.handleOpen(event);
        }
    }

    navigateTo(recordId) {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId, objectApiName: 'Veleiro_Ticket__c', actionName: 'view' }
        });
    }

    // ---------- arrastrar ----------
    handleDragStart(event) {
        this.dragId = event.currentTarget.dataset.id;
        if (event.dataTransfer) event.dataTransfer.effectAllowed = 'move';
    }
    handleDragEnd() {
        this.dragId = undefined;
        this.dropStage = undefined;
    }
    handleDragOver(event) {
        event.preventDefault();
        const stage = event.currentTarget.dataset.stage;
        if (this.dropStage !== stage) this.dropStage = stage;
    }
    handleDragLeave(event) {
        if (this.dropStage === event.currentTarget.dataset.stage) this.dropStage = undefined;
    }

    handleDrop(event) {
        event.preventDefault();
        const stage = event.currentTarget.dataset.stage;
        const recordId = this.dragId;
        this.dropStage = undefined;
        this.dragId = undefined;
        if (!recordId || !stage) return;

        const card = (this.board.cards || []).find((c) => c.recordId === recordId);
        if (!card || card.stage === stage) return;

        this.moving = true;
        moveTicket({ recordId, stage })
            .then((r) => {
                if (!r || !r.moved) {
                    const key = MOVE_MESSAGE[r && r.code];
                    this.toast(this.labels.couldNotMove, key ? this.labels[key] : (r && r.error) || '', 'warning');
                    return null;
                }
                // Se mueve la tarjeta en el momento y se recarga detras: la vista no parpadea.
                this.board = {
                    ...this.board,
                    cards: this.board.cards.map((c) =>
                        c.recordId === recordId
                            ? { ...c, stage: r.stage, statusName: r.statusName }
                            : c
                    )
                };
                this.toast(this.labels.moved, r.statusName || '', 'success');
                return refreshApex(this.wiredResult);
            })
            .catch((e) => this.toast(this.labels.couldNotMove, this.messageOf(e), 'error'))
            .finally(() => { this.moving = false; });
    }

    // ---------- traer y recargar ----------
    handleRefresh() {
        return refreshApex(this.wiredResult);
    }

    handlePull() {
        this.pulling = true;
        pullNow()
            .then((r) => {
                if (r && r.error) this.toast(this.labels.couldNotPull, r.error, 'warning');
                else this.toast(this.labels.upToDate, fmt(this.labels.pulled, [r.pulled, r.projects]), 'success');
                return refreshApex(this.wiredResult);
            })
            .catch((e) => this.toast(this.labels.couldNotPull, this.messageOf(e), 'error'))
            .finally(() => { this.pulling = false; });
    }

    messageOf(e) {
        return (e && e.body && e.body.message) || (e && e.message) || '';
    }
    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
