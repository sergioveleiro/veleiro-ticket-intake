/**
 * Lo que necesita la vista avanzada: los tickets de una sola vez y el movimiento de etapa.
 *
 * Se mandan todos los tickets (con tope) y el filtrado pasa en el navegador: son los tickets de
 * UN cliente, caben de sobra, y filtrar sin ir al servidor es la diferencia entre una vista que
 * se siente viva y una que parpadea en cada tecla. Si se llega al tope la vista lo dice en vez
 * de mentir con un numero incompleto.
 */
public with sharing class VeleiroTicketBoardController {

    @TestVisible private static Integer maxRows = 2000;

    // El orden de las columnas del tablero. Es el flujo del trabajo, no el orden alfabetico.
    private static final List<String> STAGE_ORDER = new List<String>{
        'initial', 'in_progress', 'blocked', 'review', 'terminal'
    };

    public class Card {
        @AuraEnabled public Id recordId;
        @AuraEnabled public String name;        // TKT-00001
        @AuraEnabled public String key;         // la llave de la task en Veleiro
        @AuraEnabled public String title;
        @AuraEnabled public String stage;       // state_type
        @AuraEnabled public String statusName;  // como se llama el estado en Veleiro
        @AuraEnabled public String priority;
        @AuraEnabled public String ticketType;
        @AuraEnabled public String project;
        @AuraEnabled public String projectId;
        @AuraEnabled public String assignees;
        @AuraEnabled public List<String> labels;
        @AuraEnabled public Date dueDate;
        @AuraEnabled public Datetime updated;
        @AuraEnabled public Datetime created;
        @AuraEnabled public Boolean archived;
        @AuraEnabled public Integer files;
        @AuraEnabled public String taskUrl;
        @AuraEnabled public String syncError;
        @AuraEnabled public String owner;
    }

    public class Board {
        @AuraEnabled public List<String> stages = STAGE_ORDER;
        @AuraEnabled public List<Card> cards = new List<Card>();
        @AuraEnabled public List<String> projects = new List<String>();
        @AuraEnabled public List<String> priorities = new List<String>();
        @AuraEnabled public List<String> assignees = new List<String>();
        @AuraEnabled public Boolean truncated = false;
        @AuraEnabled public String boardUrl;   // el tablero del partner en Veleiro, si hay proyecto
    }

    @AuraEnabled(cacheable=true)
    public static Board load() {
        Board b = new Board();
        Set<String> projects = new Set<String>();
        Set<String> priorities = new Set<String>();
        Set<String> assignees = new Set<String>();

        List<Veleiro_Ticket__c> rows = [
            SELECT Id, Name, Title__c, Veleiro_Task_Key__c, Veleiro_Task_Url__c, Work_Status__c,
                   Veleiro_Status__c, Priority__c, Ticket_Type__c, Veleiro_Project_Name__c,
                   Veleiro_Project_Id__c, Assignees__c, Labels__c, Due_Date__c, Veleiro_Updated_At__c,
                   CreatedDate, Is_Archived__c, Attachment_Count__c, Sync_Error__c, Owner.Name
            FROM Veleiro_Ticket__c
            ORDER BY Veleiro_Updated_At__c DESC NULLS LAST, CreatedDate DESC
            LIMIT :maxRows
        ];
        b.truncated = rows.size() == maxRows;

        for (Veleiro_Ticket__c t : rows) {
            Card c = new Card();
            c.recordId = t.Id;
            c.name = t.Name;
            c.key = t.Veleiro_Task_Key__c;
            c.title = t.Title__c;
            // Un ticket sin etapa todavia no bajo de Veleiro: vive en la primera columna.
            c.stage = String.isBlank(t.Work_Status__c) ? 'initial' : t.Work_Status__c;
            c.statusName = t.Veleiro_Status__c;
            c.priority = t.Priority__c;
            c.ticketType = t.Ticket_Type__c;
            c.project = t.Veleiro_Project_Name__c;
            c.projectId = t.Veleiro_Project_Id__c;
            c.assignees = t.Assignees__c;
            c.labels = split(t.Labels__c);
            c.dueDate = t.Due_Date__c;
            c.updated = t.Veleiro_Updated_At__c;
            c.created = t.CreatedDate;
            c.archived = t.Is_Archived__c == true;
            c.files = t.Attachment_Count__c == null ? 0 : Integer.valueOf(t.Attachment_Count__c);
            c.taskUrl = t.Veleiro_Task_Url__c;
            c.syncError = t.Sync_Error__c;
            c.owner = t.Owner.Name;
            b.cards.add(c);

            if (String.isNotBlank(c.project)) projects.add(c.project);
            if (String.isNotBlank(c.priority)) priorities.add(c.priority);
            for (String a : split(t.Assignees__c)) assignees.add(a);
        }

        b.projects = sorted(projects);
        b.priorities = sorted(priorities);
        b.assignees = sorted(assignees);

        Veleiro_Ticket_Config__c cfg = Veleiro_Ticket_Config__c.getOrgDefaults();
        String projectId = (cfg == null) ? null : cfg.Veleiro_Project_Id__c;
        if (String.isBlank(projectId)) {
            for (Veleiro_Ticket_Project__c p : [
                SELECT Veleiro_Project_Id__c FROM Veleiro_Ticket_Project__c
                WHERE Active__c = true ORDER BY Name LIMIT 1
            ]) {
                projectId = p.Veleiro_Project_Id__c;
            }
        }
        if (String.isNotBlank(projectId)) {
            b.boardUrl = VeleiroTicketApiClient.appBaseUrl() + '/a/partner-portal/projects/' + projectId;
        }
        return b;
    }

    // Arrastrar una tarjeta. Hace callout, asi que no es cacheable.
    @AuraEnabled
    public static VeleiroTicketMove.Result move(String recordId, String stage) {
        return VeleiroTicketMove.toStage((Id) recordId, stage);
    }

    private static List<String> split(String raw) {
        List<String> out = new List<String>();
        if (String.isBlank(raw)) return out;
        for (String part : raw.split(',')) {
            String v = part.trim();
            if (String.isNotBlank(v)) out.add(v);
        }
        return out;
    }

    private static List<String> sorted(Set<String> values) {
        List<String> out = new List<String>(values);
        out.sort();
        return out;
    }
}
