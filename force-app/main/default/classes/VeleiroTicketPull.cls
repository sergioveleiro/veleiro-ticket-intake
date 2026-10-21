/**
 * Trae a Salesforce los tickets que viven en Veleiro.
 *
 * Veleiro manda: lo que baja pisa lo que haya en Salesforce para los campos que son suyos
 * (estado, asignados, etiquetas, archivos). Los campos propios de Salesforce —quien lo
 * levanto, el registro de origen, la descripcion de los que nacieron aqui— no se tocan:
 * el upsert solo escribe los campos que se le ponen.
 *
 * Veleiro no tiene webhooks, asi que esto es sondeo. La propia API dice como hacerlo bien:
 * seguir `updated_since`, arrancar unos minutos antes de lo ultimo procesado porque una
 * escritura puede confirmarse despues de su `updated_at`, y tratar la entrega como
 * at-least-once resolviendo por `id`. Eso es exactamente lo que hace OVERLAP_MINUTES mas
 * el upsert por Veleiro_Task_Id__c, que es external id unico.
 */
public with sharing class VeleiroTicketPull {

    // La API avisa que un write puede confirmarse despues de su updated_at: se relee ese margen.
    @TestVisible private static Integer overlapMinutes = 5;
    // Tope por corrida: una org del cliente comparte sus limites con sus propios procesos.
    @TestVisible private static Integer maxPerRun = 2000;

    public class Result {
        @AuraEnabled public Integer projects = 0;
        @AuraEnabled public Integer pulled = 0;
        @AuraEnabled public Integer failed = 0;
        @AuraEnabled public String error;
    }

    /**
     * Una corrida completa: todos los callouts primero, el DML al final. Por eso NO se puede
     * llamar dos veces en la misma transaccion — la segunda truena con "uncommitted work
     * pending". Cada disparo (el job, el boton) es su propia transaccion.
     */
    public static Result run() {
        Result r = new Result();
        List<Veleiro_Ticket_Project__c> projects = [
            SELECT Id, Name, Veleiro_Project_Id__c, Last_Pulled_At__c
            FROM Veleiro_Ticket_Project__c
            WHERE Active__c = true AND Veleiro_Project_Id__c != null
            ORDER BY Last_Pulled_At__c NULLS FIRST
        ];
        if (projects.isEmpty()) return r;

        // Un solo listado de estados y de miembros para toda la corrida, no uno por ticket.
        Map<String, String> stateTypeById;
        Map<String, String> memberNameById;
        try {
            stateTypeById = loadStateTypes();
            memberNameById = loadMembers();
        } catch (Exception e) {
            r.error = e.getMessage();
            return r;
        }

        // El nombre del proyecto se resuelve aqui: la task solo trae el id.
        Map<String, String> projectNameById = new Map<String, String>();
        for (Veleiro_Ticket_Project__c p : projects) projectNameById.put(p.Veleiro_Project_Id__c, p.Name);

        List<Veleiro_Ticket__c> toSave = new List<Veleiro_Ticket__c>();
        Map<Id, Datetime> watermark = new Map<Id, Datetime>();

        for (Veleiro_Ticket_Project__c p : projects) {
            if (toSave.size() >= maxPerRun) break;
            r.projects++;
            try {
                Datetime newest = p.Last_Pulled_At__c;
                for (Object o : VeleiroTicketApiClient.listAll('/tasks', filtersFor(p))) {
                    Map<String, Object> task = (Map<String, Object>) o;
                    toSave.add(toTicket(task, p, stateTypeById, memberNameById, projectNameById));
                    Datetime updated = parseStamp((String) task.get('updated_at'));
                    if (updated != null && (newest == null || updated > newest)) newest = updated;
                    if (toSave.size() >= maxPerRun) break;
                }
                if (newest != null) watermark.put(p.Id, newest);
            } catch (Exception e) {
                r.error = p.Name + ': ' + e.getMessage();
            }
        }

        if (!toSave.isEmpty()) {
            // Parcial: una regla de validacion del cliente sobre un ticket no tumba la corrida.
            Schema.SObjectField key = Veleiro_Ticket__c.Veleiro_Task_Id__c;
            for (Database.UpsertResult ur : Database.upsert(toSave, key, false)) {
                if (ur.isSuccess()) { r.pulled++; }
                else {
                    r.failed++;
                    if (r.error == null && !ur.getErrors().isEmpty()) r.error = ur.getErrors()[0].getMessage();
                }
            }
        }

        // La marca de agua solo avanza para lo que de verdad se guardo.
        List<Veleiro_Ticket_Project__c> moved = new List<Veleiro_Ticket_Project__c>();
        for (Veleiro_Ticket_Project__c p : projects) {
            if (!watermark.containsKey(p.Id)) continue;
            moved.add(new Veleiro_Ticket_Project__c(Id = p.Id, Last_Pulled_At__c = watermark.get(p.Id)));
        }
        if (!moved.isEmpty()) Database.update(moved, false);
        return r;
    }

    private static Map<String, String> filtersFor(Veleiro_Ticket_Project__c p) {
        Map<String, String> f = new Map<String, String>{
            'project_id' => p.Veleiro_Project_Id__c,
            // Archivados incluidos a proposito: es la unica forma de enterarse de que un
            // ticket se archivo en Veleiro en vez de verlo quedarse quieto para siempre.
            'include_archived' => 'true'
        };
        if (p.Last_Pulled_At__c != null) {
            f.put('updated_since', p.Last_Pulled_At__c.addMinutes(-overlapMinutes).formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\''));
        }
        return f;
    }

    private static Veleiro_Ticket__c toTicket(Map<String, Object> task, Veleiro_Ticket_Project__c p,
                                              Map<String, String> stateTypeById,
                                              Map<String, String> memberNameById,
                                              Map<String, String> projectNameById) {
        Veleiro_Ticket__c t = new Veleiro_Ticket__c();
        t.Veleiro_Task_Id__c = (String) task.get('id');
        t.Title__c = abbrev((String) task.get('title'), 255);
        t.Veleiro_Task_Key__c = (String) task.get('key');
        // La URL viene lista de la API: se guarda tal cual en vez de construirla.
        t.Veleiro_Task_Url__c = (String) task.get('url');
        t.Veleiro_Status__c = (String) task.get('status');
        t.Veleiro_Status_Id__c = (String) task.get('status_id');
        t.Work_Status__c = stateTypeById.get((String) task.get('status_id'));
        t.Ticket_Type__c = titled((String) task.get('ticket_type'));
        t.Priority__c = titled((String) task.get('priority'));
        t.Veleiro_Client_Id__c = (String) task.get('client_id');
        t.Veleiro_Project_Id__c = (String) task.get('project_id');
        t.Veleiro_Project_Name__c = projectNameById.containsKey((String) task.get('project_id'))
            ? projectNameById.get((String) task.get('project_id'))
            : p.Name;
        t.Is_Archived__c = (task.get('is_archived') == true);
        t.Veleiro_Version__c = numberOf(task.get('version'));
        t.Veleiro_Updated_At__c = parseStamp((String) task.get('updated_at'));
        t.Assignees__c = abbrev(namesOf(task.get('assignee_ids'), memberNameById), 255);
        t.Labels__c = abbrev(joinOf(task.get('labels')), 255);
        t.Attachment_Count__c = sizeOf(task.get('files'));
        t.Last_Sync__c = System.now();
        // Un ticket que baja de Veleiro ya esta sincronizado por definicion.
        t.Status__c = 'Sent';
        t.Sync_Error__c = null;
        return t;
    }

    // ---- catalogos de la corrida ----

    private static Map<String, String> loadStateTypes() {
        Map<String, String> byId = new Map<String, String>();
        for (Object o : VeleiroTicketApiClient.listAll('/tasks/states', null)) {
            Map<String, Object> s = (Map<String, Object>) o;
            byId.put((String) s.get('id'), (String) s.get('state_type'));
        }
        return byId;
    }

    // Los asignados son gente del partner: en la org del cliente no existen como usuarios,
    // asi que se guardan como nombre y no como lookup.
    private static Map<String, String> loadMembers() {
        Map<String, String> byId = new Map<String, String>();
        try {
            for (Object o : VeleiroTicketApiClient.listAll('/members', null)) {
                Map<String, Object> m = (Map<String, Object>) o;
                byId.put((String) m.get('id'), (String) m.get('name'));
            }
        } catch (Exception e) {
            // Sin scope member:read el resto de la bajada sigue sirviendo: se pierde el nombre.
            System.debug(LoggingLevel.WARN, 'Sin acceso a /members: ' + e.getMessage());
        }
        return byId;
    }

    // ---- utilerias ----

    private static String namesOf(Object ids, Map<String, String> names) {
        if (!(ids instanceof List<Object>)) return null;
        List<String> out = new List<String>();
        for (Object o : (List<Object>) ids) {
            String id = String.valueOf(o);
            out.add(names.containsKey(id) ? names.get(id) : id);
        }
        return out.isEmpty() ? null : String.join(out, ', ');
    }

    private static String joinOf(Object raw) {
        if (!(raw instanceof List<Object>)) return null;
        List<String> out = new List<String>();
        for (Object o : (List<Object>) raw) out.add(String.valueOf(o));
        return out.isEmpty() ? null : String.join(out, ', ');
    }

    private static Integer sizeOf(Object raw) {
        return (raw instanceof List<Object>) ? ((List<Object>) raw).size() : 0;
    }

    private static Decimal numberOf(Object v) {
        return (v == null) ? null : Decimal.valueOf(String.valueOf(v));
    }

    private static String abbrev(String s, Integer max) {
        return String.isBlank(s) ? s : s.abbreviate(max);
    }

    // 'bug' -> 'Bug': los picklists de Salesforce vienen capitalizados.
    private static String titled(String s) {
        if (String.isBlank(s)) return null;
        return s.substring(0, 1).toUpperCase() + s.substring(1).toLowerCase();
    }

    /**
     * Las marcas de la API vienen como 2026-10-08T23:01:40.149330+00:00: microsegundos y
     * offset. JSON.deserialize no se las traga, y una fecha nula hace que la marca de agua
     * nunca avance — el sondeo dejaria de ser incremental y recorreria todo cada hora.
     *
     * Se toman los 19 primeros caracteres, que son fecha y hora al segundo, y se leen como
     * UTC: la API entrega todo en UTC (+00:00 o Z).
     */
    @TestVisible
    private static Datetime parseStamp(String iso) {
        if (String.isBlank(iso) || iso.length() < 19) return null;
        try {
            return Datetime.valueOfGmt(iso.substring(0, 19).replace('T', ' '));
        } catch (Exception e) {
            return null;
        }
    }
}
