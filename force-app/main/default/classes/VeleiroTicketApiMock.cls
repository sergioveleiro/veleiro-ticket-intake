/**
 * Mock reutilizable de la API de Veleiro para los tests (HttpCalloutMock).
 * Enruta por recurso (/clients, /projects, /tasks, /tasks/states) y metodo.
 */
@isTest
public class VeleiroTicketApiMock implements HttpCalloutMock {

    public String clientsBody  = '{"data":[],"has_more":false}';
    public String projectsBody = '{"data":[],"has_more":false}';
    public String tasksBody    = '{"data":[],"has_more":false}';
    public String statesBody   = '{"data":[]}';

    public String postTaskBody   = '{"data":{"id":"task_test","key":"CLF-1","title":"T","status":"Backlog","status_id":"st_1","version":1,"additional_fields":{}}}';
    public String singleTaskBody = '{"data":{"id":"task_test","key":"CLF-1","title":"T","status":"In Progress","status_id":"st_2","version":2,"additional_fields":{}}}';

    public Integer overrideStatus = null;
    public String  overrideBody   = null;

    public String lastPostBody;
    public String lastPatchBody;

    public HttpResponse respond(HttpRequest req) {
        HttpResponse res = new HttpResponse();
        res.setHeader('Content-Type', 'application/json');
        String url = req.getEndpoint();
        String m = req.getMethod();

        if (m == 'POST') lastPostBody = req.getBody();
        else if (m == 'PATCH') lastPatchBody = req.getBody();

        if (overrideStatus != null) {
            res.setStatusCode(overrideStatus);
            res.setBody(overrideBody != null ? overrideBody : '{"error":{"code":"internal_error"}}');
            return res;
        }

        res.setStatusCode(200);
        if (url.contains('/tasks/states')) {
            res.setBody(statesBody);
        } else if (m == 'POST' && url.contains('/tasks')) {
            res.setStatusCode(201);
            res.setBody(postTaskBody);
        } else if (m == 'PATCH' && url.contains('/tasks/')) {
            res.setBody(singleTaskBody);
        } else if (url.contains('/clients')) {
            res.setBody(clientsBody);
        } else if (url.contains('/projects')) {
            res.setBody(projectsBody);
        } else if (url.contains('/tasks')) {
            res.setBody(tasksBody);
        } else {
            res.setBody('{"data":[]}');
        }
        return res;
    }

    // Inserta el Veleiro_Ticket_Config__c org-default (token + mapping) para que las clases no truenen.
    public static void seedConfig() {
        insert new Veleiro_Ticket_Config__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Api_Token__c = 'test-token',
            Base_Url__c  = 'https://test.veleiro.local/api/v1',
            App_Base_Url__c = 'https://app.test.veleiro.local',
            Veleiro_Client_Id__c = 'org_test',
            Veleiro_Client_Name__c = 'Colfondos',
            Veleiro_Project_Id__c = 'prjct_test',
            Veleiro_Project_Name__c = 'Implementation'
        );
    }
}
