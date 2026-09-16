/**
 * Logica de negocio del intake de tickets -> tasks de Veleiro.
 *  - listClients / listProjects: para el panel de mapping (dropdowns de datos reales de Veleiro).
 *  - pushTicket: crea la task en Veleiro y guarda el match en el Veleiro_Ticket__c.
 *
 * El API de Veleiro NO recibe archivos (no hay endpoint de upload): los adjuntos viven
 * en Salesforce (Files) y solo la URL de contexto viaja en additional_fields.
 */
public with sharing class VeleiroTicketService {

    // Opcion simple para los dropdowns del panel de config (id + nombre).
    public class Option {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        public Option(String id, String name) { this.id = id; this.name = name; }
    }

    public static List<Option> listClients() {
        List<Option> out = new List<Option>();
        for (Object o : VeleiroTicketApiClient.listAll('/clients', null)) {
            Map<String, Object> c = (Map<String, Object>) o;
            if (c.get('is_archived') == true) continue;
            out.add(new Option((String) c.get('id'), (String) c.get('name')));
        }
        return out;
    }

    public static List<Option> listProjects(String clientId) {
        List<Option> out = new List<Option>();
        for (Object o : VeleiroTicketApiClient.listAll('/projects', null)) {
            Map<String, Object> p = (Map<String, Object>) o;
            if (p.get('is_archived') == true) continue;
            if (String.isNotBlank(clientId) && clientId != (String) p.get('client_id')) continue;
            out.add(new Option((String) p.get('id'), (String) p.get('name')));
        }
        return out;
    }

    // Empuja el ticket a Veleiro. Corre en contexto async (Queueable) para hacer callout.
    // NO relanza: registra el resultado (Sent/Error) en el propio registro para que el usuario lo vea.
    public static void pushTicket(Id ticketId) {
        Veleiro_Ticket__c t = [
            SELECT Id, Name, Title__c, Description__c, Ticket_Type__c, Priority__c, Due_Date__c,
                   Source_URL__c, SF_Record_Id__c, SF_Object__c, SF_Record_Name__c,
                   Veleiro_Client_Id__c, Veleiro_Project_Id__c, Veleiro_Task_Id__c, Veleiro_Version__c,
                   Submitted_By_Name__c, Submitted_By_Email__c
            FROM Veleiro_Ticket__c WHERE Id = :ticketId LIMIT 1
        ];
        try {
            Map<String, Object> af = new Map<String, Object>();
            putIf(af, 'sf_record_url', t.Source_URL__c);
            putIf(af, 'sf_object', t.SF_Object__c);
            putIf(af, 'sf_record_id', t.SF_Record_Id__c);
            putIf(af, 'sf_record_name', t.SF_Record_Name__c);
            putIf(af, 'sf_submitted_by', t.Submitted_By_Name__c);
            putIf(af, 'sf_submitted_by_email', t.Submitted_By_Email__c);
            af.put('sf_ticket_number', t.Name);

            Map<String, Object> payload = new Map<String, Object>();
            payload.put('title', t.Title__c);
            payload.put('description', buildDescription(t));
            payload.put('ticket_type', normType(t.Ticket_Type__c));
            payload.put('priority', normPriority(t.Priority__c));
            putIf(payload, 'client_id', t.Veleiro_Client_Id__c);
            putIf(payload, 'project_id', t.Veleiro_Project_Id__c);
            payload.put('additional_fields', af);

            Map<String, Object> task = VeleiroTicketApiClient.doPost('/tasks', payload);
            String taskId = (String) task.get('id');
            Integer version = intOf(task.get('version'));

            // due_date NO va en create -> PATCH aparte (If-Match con la version recien creada).
            if (t.Due_Date__c != null && String.isNotBlank(taskId)) {
                Map<String, Object> patch = new Map<String, Object>{ 'due_date' => String.valueOf(t.Due_Date__c) };
                Map<String, Object> updated = VeleiroTicketApiClient.doPatch('/tasks/' + taskId, patch, version);
                if (updated != null) {
                    task = updated;
                    version = intOf(task.get('version'));
                }
            }

            t.Veleiro_Task_Id__c = taskId;
            t.Veleiro_Task_Key__c = (String) task.get('key');
            t.Veleiro_Version__c = version;
            t.Veleiro_Status__c = (String) task.get('status');
            t.Veleiro_Task_Url__c = taskUrl(t);
            t.Status__c = 'Sent';
            t.Sync_Error__c = null;
            t.Last_Sync__c = System.now();
        } catch (Exception e) {
            t.Status__c = 'Error';
            t.Sync_Error__c = e.getMessage();
            t.Last_Sync__c = System.now();
        }
        update t;
    }

    private static String buildDescription(Veleiro_Ticket__c t) {
        String d = String.isBlank(t.Description__c) ? '' : t.Description__c;
        List<String> ctx = new List<String>();
        if (String.isNotBlank(t.Source_URL__c)) ctx.add('Source: ' + t.Source_URL__c);
        if (String.isNotBlank(t.SF_Object__c)) {
            ctx.add('Object: ' + t.SF_Object__c + (String.isNotBlank(t.SF_Record_Id__c) ? ' (' + t.SF_Record_Id__c + ')' : ''));
        }
        if (String.isNotBlank(t.Submitted_By_Name__c)) ctx.add('Raised by: ' + t.Submitted_By_Name__c);
        ctx.add('Salesforce ticket: ' + t.Name);
        return d + '\n\n---\n' + String.join(ctx, '\n');
    }

    private static String taskUrl(Veleiro_Ticket__c t) {
        String base = VeleiroTicketApiClient.appBaseUrl();
        if (String.isNotBlank(t.Veleiro_Client_Id__c)) {
            return base + '/a/partner-portal/organizations/' + t.Veleiro_Client_Id__c;
        }
        return base;
    }

    private static void putIf(Map<String, Object> m, String key, String val) {
        if (String.isNotBlank(val)) m.put(key, val);
    }

    // ---- Normalizacion a los valores que ACEPTA el API de Veleiro (descubiertos por probe) ----
    // ticket_type validos: epic, story, task, decision, approval, review, deliverable, action_item, milestone, subtask
    // priority validos: low, medium, high, critical  (OJO: "urgent" NO existe -> mapea a critical)
    private static final Set<String> VALID_TYPES = new Set<String>{
        'epic', 'story', 'task', 'decision', 'approval', 'review', 'deliverable', 'action_item', 'milestone', 'subtask'
    };
    private static final Set<String> VALID_PRIORITIES = new Set<String>{ 'low', 'medium', 'high', 'critical' };

    private static String normPriority(String p) {
        if (String.isBlank(p)) return 'medium';
        String v = p.toLowerCase().trim();
        if (v == 'urgent') return 'critical';
        return VALID_PRIORITIES.contains(v) ? v : 'medium';
    }

    private static String normType(String t) {
        if (String.isBlank(t)) return 'task';
        String v = t.toLowerCase().trim().replace(' ', '_');
        if (VALID_TYPES.contains(v)) return v;
        Map<String, String> alias = new Map<String, String>{
            'bug' => 'task', 'question' => 'task', 'feature' => 'story', 'other' => 'task'
        };
        return alias.containsKey(v) ? alias.get(v) : 'task';
    }

    private static Integer intOf(Object o) {
        if (o == null) return null;
        if (o instanceof Integer) return (Integer) o;
        if (o instanceof Decimal) return ((Decimal) o).intValue();
        if (o instanceof Double) return ((Double) o).intValue();
        return Integer.valueOf(String.valueOf(o));
    }
}
