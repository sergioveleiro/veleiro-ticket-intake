/**
 * Superficie @AuraEnabled para los LWC de intake y de configuracion.
 *  - getSetup: estado de conexion + a que client/project de Veleiro manda esta org.
 *  - listClients / listProjects: dropdowns del panel de mapping (callout, cacheable=false).
 *  - saveMapping: guarda el client/project destino en el Veleiro_Config__c org-default.
 *  - createTicket: inserta el ticket (+ adjuntos como Files) y encola el push a Veleiro.
 *
 * createTicket recibe el payload como STRING JSON y hace JSON.deserialize: evita el bug
 * conocido de marshaling LWC->Apex (List<CustomClass> llega con todos los campos null).
 */
public with sharing class VeleiroTicketController {

    public class SetupInfo {
        @AuraEnabled public Boolean connected;     // hay token puesto
        @AuraEnabled public String environment;    // 'Production' | 'Beta' | 'Custom'
        @AuraEnabled public String appBase;        // URL del portal (para links)
        @AuraEnabled public String tokenMasked;    // token enmascarado para el UI
        @AuraEnabled public String clientId;
        @AuraEnabled public String clientName;
        @AuraEnabled public String projectId;
        @AuraEnabled public String projectName;
    }

    @AuraEnabled(cacheable=false)
    public static SetupInfo getSetup() {
        SetupInfo s = new SetupInfo();
        s.connected = VeleiroApiClient.hasToken();
        String app = VeleiroApiClient.appBaseUrl();
        s.appBase = app;
        s.environment = app.containsIgnoreCase('beta') ? 'Beta'
            : (app.containsIgnoreCase('app.veleiro.ai') ? 'Production' : 'Custom');
        Veleiro_Config__c c = Veleiro_Config__c.getOrgDefaults();
        if (c != null) {
            s.tokenMasked = maskToken(c.Api_Token__c);
            s.clientId = c.Veleiro_Client_Id__c;
            s.clientName = c.Veleiro_Client_Name__c;
            s.projectId = c.Veleiro_Project_Id__c;
            s.projectName = c.Veleiro_Project_Name__c;
        }
        return s;
    }

    // Guarda el token (Org Default). Si viene en blanco NO lo pisa (para editar solo el entorno).
    @AuraEnabled
    public static void saveToken(String token) {
        if (String.isBlank(token)) return;
        Veleiro_Config__c c = orgDefault();
        c.Api_Token__c = token.trim();
        upsert c;
    }

    // Cambia el entorno (Production / Beta) escribiendo Base_Url + App_Base_Url. NO toca el token.
    // El host real lo enruta el Named Credential correspondiente (Veleiro_API / Veleiro_API_Beta).
    @AuraEnabled
    public static void saveEnvironment(String environment) {
        Veleiro_Config__c c = orgDefault();
        if (environment == 'Beta') {
            c.Base_Url__c = 'callout:Veleiro_API_Beta/api/v1';
            c.App_Base_Url__c = 'https://app.beta.veleiro.dev';
        } else { // Production (default)
            c.Base_Url__c = 'callout:Veleiro_API/api/v1';
            c.App_Base_Url__c = 'https://app.veleiro.ai';
        }
        upsert c;
    }

    private static Veleiro_Config__c orgDefault() {
        Veleiro_Config__c c = Veleiro_Config__c.getOrgDefaults();
        if (c == null || c.Id == null) {
            c = new Veleiro_Config__c(SetupOwnerId = UserInfo.getOrganizationId());
        }
        return c;
    }

    private static String maskToken(String tok) {
        if (String.isBlank(tok)) return null;
        String last = tok.length() > 4 ? tok.substring(tok.length() - 4) : tok;
        return '••••••••' + last;
    }

    @AuraEnabled(cacheable=false)
    public static List<VeleiroTicketService.Option> listClients() {
        return VeleiroTicketService.listClients();
    }

    @AuraEnabled(cacheable=false)
    public static List<VeleiroTicketService.Option> listProjects(String clientId) {
        return VeleiroTicketService.listProjects(clientId);
    }

    @AuraEnabled
    public static void saveMapping(String clientId, String clientName, String projectId, String projectName) {
        Veleiro_Config__c c = Veleiro_Config__c.getOrgDefaults();
        if (c == null || c.Id == null) {
            c = new Veleiro_Config__c(SetupOwnerId = UserInfo.getOrganizationId());
        }
        c.Veleiro_Client_Id__c = clientId;
        c.Veleiro_Client_Name__c = clientName;
        c.Veleiro_Project_Id__c = String.isBlank(projectId) ? null : projectId;
        c.Veleiro_Project_Name__c = String.isBlank(projectId) ? null : projectName;
        upsert c;
    }

    @AuraEnabled
    public static Id createTicket(String payloadJson) {
        TicketInput inp = (TicketInput) JSON.deserialize(payloadJson, TicketInput.class);
        if (inp == null || String.isBlank(inp.title)) {
            throw new AuraHandledException('El titulo es obligatorio.');
        }
        Veleiro_Config__c c = Veleiro_Config__c.getOrgDefaults();

        Veleiro_Ticket__c t = new Veleiro_Ticket__c();
        t.Title__c = trunc(inp.title, 255);
        t.Description__c = inp.description;
        t.Ticket_Type__c = String.isBlank(inp.ticketType) ? 'Task' : inp.ticketType;
        t.Priority__c = String.isBlank(inp.priority) ? 'Medium' : inp.priority;
        if (String.isNotBlank(inp.dueDate)) {
            try { t.Due_Date__c = Date.valueOf(inp.dueDate); } catch (Exception e) { /* fecha invalida -> ignora */ }
        }
        t.Source_URL__c = trunc(inp.sourceUrl, 255);
        t.SF_Record_Id__c = trunc(inp.sfRecordId, 18);
        t.SF_Object__c = trunc(inp.sfObject, 80);
        t.SF_Record_Name__c = trunc(inp.sfRecordName, 255);
        t.Status__c = 'New';
        t.Submitted_By_Name__c = UserInfo.getName();
        t.Submitted_By_Email__c = UserInfo.getUserEmail();
        if (c != null) {
            t.Veleiro_Client_Id__c = c.Veleiro_Client_Id__c;
            t.Veleiro_Project_Id__c = c.Veleiro_Project_Id__c;
        }
        insert t;

        if (inp.files != null && !inp.files.isEmpty()) {
            attachFiles(t.Id, inp.files);
        }

        // Push async solo si hay token; si no, el ticket queda guardado en Salesforce.
        if (VeleiroApiClient.hasToken()) {
            System.enqueueJob(new VeleiroTicketPushQueueable(t.Id));
        }
        return t.Id;
    }

    private static void attachFiles(Id ticketId, List<FileInput> files) {
        List<ContentVersion> cvs = new List<ContentVersion>();
        for (FileInput f : files) {
            if (f == null || String.isBlank(f.base64)) continue;
            ContentVersion cv = new ContentVersion();
            cv.Title = String.isBlank(f.name) ? 'attachment' : f.name;
            cv.PathOnClient = cv.Title;
            cv.VersionData = EncodingUtil.base64Decode(f.base64);
            cvs.add(cv);
        }
        if (cvs.isEmpty()) return;
        insert cvs;
        Set<Id> cvIds = new Set<Id>();
        for (ContentVersion cv : cvs) cvIds.add(cv.Id);
        List<ContentDocumentLink> links = new List<ContentDocumentLink>();
        for (ContentVersion cv : [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id IN :cvIds]) {
            links.add(new ContentDocumentLink(
                ContentDocumentId = cv.ContentDocumentId,
                LinkedEntityId = ticketId,
                ShareType = 'V',
                Visibility = 'AllUsers'
            ));
        }
        insert links;
    }

    private static String trunc(String s, Integer n) {
        if (s == null) return null;
        return s.length() > n ? s.substring(0, n) : s;
    }

    // ---- payload que viaja como string JSON desde el LWC ----
    public class TicketInput {
        public String title;
        public String description;
        public String ticketType;
        public String priority;
        public String dueDate;      // 'YYYY-MM-DD'
        public String sourceUrl;
        public String sfRecordId;
        public String sfObject;
        public String sfRecordName;
        public List<FileInput> files;
    }
    public class FileInput {
        public String name;
        public String base64;
        public String contentType;
    }
}
