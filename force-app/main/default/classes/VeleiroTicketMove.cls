/**
 * Mover un ticket de etapa desde Salesforce, y que Veleiro se entere.
 *
 * Este es el lado que faltaba: arrastrar una tarjeta cambiaba el campo local y la siguiente
 * bajada lo borraba sin decir nada, asi que la persona creia haber movido algo que nunca se
 * movio. Ahora el orden es: validar, escribir en Veleiro, y solo entonces escribir aqui. Si
 * Veleiro rechaza, en Salesforce no cambia nada y quien arrastro se entera.
 *
 * El partner decide a que etapas puede mover su cliente con Client_Allowed_States__c (un
 * nombre o un tipo por linea, en blanco = todas). Es la razon por la que el campo del Kanban
 * tuvo que volverse editable: el candado real vive aqui, no en el permiso del campo.
 */
public with sharing class VeleiroTicketMove {

    public class Result {
        @AuraEnabled public Boolean moved = false;
        @AuraEnabled public String stage;       // state_type que quedo
        @AuraEnabled public String statusName;  // como se llama ese estado en Veleiro
        @AuraEnabled public String error;       // en idioma de API, el LWC decide como mostrarlo
        @AuraEnabled public String code;        // not_allowed | no_such_stage | not_in_veleiro | <codigo de la API>
    }

    public static Result toStage(Id recordId, String stageType) {
        Result r = new Result();

        List<Veleiro_Ticket__c> rows = [
            SELECT Id, Veleiro_Task_Id__c, Veleiro_Project_Id__c, Veleiro_Version__c,
                   Work_Status__c, Veleiro_Status__c, Veleiro_Status_Id__c
            FROM Veleiro_Ticket__c
            WHERE Id = :recordId
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            r.code = 'not_found';
            r.error = 'Ticket not found.';
            return r;
        }
        Veleiro_Ticket__c t = rows[0];

        // Un ticket que todavia no llego a Veleiro no se puede mover alla: primero tiene que subir.
        if (String.isBlank(t.Veleiro_Task_Id__c)) {
            r.code = 'not_in_veleiro';
            r.error = 'This ticket has not reached Veleiro yet.';
            return r;
        }
        if (!allowed(t.Veleiro_Project_Id__c, stageType)) {
            r.code = 'not_allowed';
            r.error = 'That stage is not open to this org.';
            return r;
        }

        VeleiroTicketStates.State target;
        try {
            target = VeleiroTicketStates.forType(stageType);
        } catch (Exception e) {
            r.code = 'api_error';
            r.error = e.getMessage();
            return r;
        }
        if (target == null) {
            r.code = 'no_such_stage';
            r.error = 'Veleiro has no state of that kind.';
            return r;
        }
        // Ya esta ahi: no se gasta una escritura ni se pisa el nombre real del estado.
        if (target.id == t.Veleiro_Status_Id__c) {
            r.moved = true;
            r.stage = stageType;
            r.statusName = t.Veleiro_Status__c;
            return r;
        }

        Map<String, Object> saved;
        try {
            Integer version = t.Veleiro_Version__c == null ? null : Integer.valueOf(t.Veleiro_Version__c);
            saved = VeleiroTicketApiClient.doPatch(
                '/tasks/' + t.Veleiro_Task_Id__c,
                new Map<String, Object>{ 'status_id' => target.id },
                version
            );
        } catch (VeleiroTicketApiClient.VeleiroApiException e) {
            // 409: alguien movio la task en Veleiro mientras mirabamos. La bajada manda.
            r.code = e.code;
            r.error = e.getMessage();
            return r;
        } catch (Exception e) {
            r.code = 'api_error';
            r.error = e.getMessage();
            return r;
        }

        // Lo que queda guardado es lo que Veleiro contesto, no lo que pedimos.
        t.Veleiro_Status_Id__c = str(saved, 'status_id', target.id);
        t.Veleiro_Status__c = str(saved, 'status', target.name);
        t.Work_Status__c = stageType;
        if (saved != null && saved.get('version') != null) {
            t.Veleiro_Version__c = Decimal.valueOf(String.valueOf(saved.get('version')));
        }
        t.Last_Sync__c = System.now();
        t.Sync_Error__c = null;
        update t;

        r.moved = true;
        r.stage = t.Work_Status__c;
        r.statusName = t.Veleiro_Status__c;
        return r;
    }

    /**
     * Client_Allowed_States__c: un estado por linea. Vale el nombre de Veleiro ("UAT") o el tipo
     * ("review"), porque el partner escribe lo que ve en su tablero. En blanco no restringe.
     */
    @TestVisible
    private static Boolean allowed(String projectId, String stageType) {
        if (String.isBlank(projectId)) return true; // sin proyecto conocido no hay regla que aplicar
        List<Veleiro_Ticket_Project__c> ps = [
            SELECT Client_Allowed_States__c FROM Veleiro_Ticket_Project__c
            WHERE Veleiro_Project_Id__c = :projectId LIMIT 1
        ];
        if (ps.isEmpty() || String.isBlank(ps[0].Client_Allowed_States__c)) return true;

        Set<String> allowList = new Set<String>();
        for (String line : ps[0].Client_Allowed_States__c.split('\n')) {
            String v = line.trim().toLowerCase();
            if (String.isNotBlank(v)) allowList.add(v);
        }
        if (allowList.contains(stageType.toLowerCase())) return true;
        // Tambien se acepta por nombre de estado, que es lo que el partner suele escribir.
        for (VeleiroTicketStates.State s : VeleiroTicketStates.all()) {
            if (stageType.equalsIgnoreCase(s.stateType) && s.name != null
                && allowList.contains(s.name.toLowerCase())) {
                return true;
            }
        }
        return false;
    }

    private static String str(Map<String, Object> m, String key, String fallback) {
        Object v = (m == null) ? null : m.get(key);
        return (v == null) ? fallback : String.valueOf(v);
    }
}
