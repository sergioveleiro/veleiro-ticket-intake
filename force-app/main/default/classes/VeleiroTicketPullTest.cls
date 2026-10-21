@isTest
private class VeleiroTicketPullTest {

    private static final String STATES =
        '{"data":[' +
        '{"id":"tckt_st_back","name":"Backlog","state_type":"initial"},' +
        '{"id":"tckt_st_prog","name":"In Progress","state_type":"in_progress"},' +
        '{"id":"tckt_st_input","name":"Input Required","state_type":"blocked"},' +
        '{"id":"tckt_st_done","name":"Done","state_type":"terminal"}' +
        '],"has_more":false}';

    @testSetup
    static void setup() {
        VeleiroTicketApiMock.seedConfig();
    }

    private static Veleiro_Ticket_Project__c project(String veleiroId, Boolean active) {
        Veleiro_Ticket_Project__c p = new Veleiro_Ticket_Project__c(
            Name = 'Implementación', Veleiro_Project_Id__c = veleiroId, Active__c = active
        );
        insert p;
        return p;
    }

    private static VeleiroTicketApiMock mockWith(String tasks) {
        VeleiroTicketApiMock m = new VeleiroTicketApiMock();
        m.statesBody = STATES;
        m.tasksBody = tasks;
        Test.setMock(HttpCalloutMock.class, m);
        return m;
    }

    private static String task(String id, String key, String statusId, String statusName, String updated) {
        return '{"id":"' + id + '","key":"' + key + '","url":"https://app.veleiro.ai/t/' + id + '",' +
               '"title":"Algo no sirve","status":"' + statusName + '","status_id":"' + statusId + '",' +
               '"ticket_type":"bug","priority":"high","client_id":"org_x","project_id":"prjct_x",' +
               '"is_archived":false,"version":3,"assignee_ids":["prtr_mem_1"],"labels":["urgente","web"],' +
               '"points":null,"logged_minutes":30,"custom_fields":[],"files":[{"id":"file_1"},{"id":"file_2"}],' +
               '"created_at":"2026-10-01T10:00:00+00:00","updated_at":"' + updated + '"}';
    }

    /**
     * Lo que llega de Veleiro tiene que quedar legible en Salesforce: el estado agrupable
     * para el Kanban, el nombre real del estado, la llave y la URL listas para abrir.
     */
    @isTest
    static void aVeleiroTicketBecomesASalesforceTicket() {
        project('prjct_x', true);
        mockWith('{"data":[' + task('tckt_1','TASK-1','tckt_st_input','Input Required','2026-10-15T08:00:00+00:00') + '],"has_more":false}');

        Test.startTest();
        VeleiroTicketPull.Result r = VeleiroTicketPull.run();
        Test.stopTest();

        System.assertEquals(1, r.pulled);
        System.assertEquals(0, r.failed, 'sin fallos, error=' + r.error);
        Veleiro_Ticket__c t = [
            SELECT Title__c, Work_Status__c, Veleiro_Status__c, Veleiro_Status_Id__c, Veleiro_Task_Key__c,
                   Veleiro_Task_Url__c, Ticket_Type__c, Priority__c, Assignees__c, Labels__c,
                   Attachment_Count__c, Status__c, Is_Archived__c, Veleiro_Updated_At__c
            FROM Veleiro_Ticket__c
        ];
        System.assertEquals('Algo no sirve', t.Title__c);
        System.assertEquals('blocked', t.Work_Status__c, 'el Kanban agrupa por el tipo de estado');
        System.assertEquals('Input Required', t.Veleiro_Status__c, 'y la tarjeta muestra el nombre real');
        System.assertEquals('tckt_st_input', t.Veleiro_Status_Id__c,
            'el id distingue dos estados que comparten tipo');
        System.assertEquals('TASK-1', t.Veleiro_Task_Key__c);
        System.assertEquals('https://app.veleiro.ai/t/tckt_1', t.Veleiro_Task_Url__c);
        System.assertEquals('Bug', t.Ticket_Type__c, 'el picklist de Salesforce va capitalizado');
        System.assertEquals('High', t.Priority__c);
        System.assertEquals('urgente, web', t.Labels__c);
        System.assertEquals(2, t.Attachment_Count__c, 'se cuenta los archivos, no se copian');
        System.assertEquals('Sent', t.Status__c, 'lo que baja ya esta sincronizado');
        System.assertNotEquals(null, t.Veleiro_Updated_At__c);
    }

    // La entrega es at-least-once: un task que ya existe se actualiza, no se duplica.
    @isTest
    static void aTaskAlreadyInSalesforceIsUpdatedNotDuplicated() {
        project('prjct_x', true);
        insert new Veleiro_Ticket__c(Title__c = 'Version vieja', Veleiro_Task_Id__c = 'tckt_1',
                                     Veleiro_Status__c = 'Backlog');
        mockWith('{"data":[' + task('tckt_1','TASK-1','tckt_st_prog','In Progress','2026-10-15T08:00:00+00:00') + '],"has_more":false}');

        Test.startTest();
        VeleiroTicketPull.run();
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM Veleiro_Ticket__c], 'upsert por el external id');
        Veleiro_Ticket__c t = [SELECT Title__c, Veleiro_Status__c FROM Veleiro_Ticket__c];
        System.assertEquals('Algo no sirve', t.Title__c, 'se quedo con lo que dice Veleiro');
        System.assertEquals('In Progress', t.Veleiro_Status__c);
    }

    /**
     * Con marca de agua, la corrida no vuelve a pedir todo: pregunta por lo que cambió, y
     * arranca unos minutos antes porque la API avisa que un write puede confirmarse despues
     * de su updated_at.
     *
     * Se simula la marca en vez de correr dos veces: una corrida hace callouts y despues DML,
     * asi que dos en la misma transaccion chocan con "uncommitted work pending".
     */
    @isTest
    static void aRunWithAWatermarkOnlyAsksForWhatChanged() {
        Veleiro_Ticket_Project__c p = project('prjct_x', true);
        p.Last_Pulled_At__c = Datetime.newInstanceGmt(2026, 10, 15, 8, 0, 0);
        update p;
        VeleiroTicketApiMock m = mockWith('{"data":[' + task('tckt_2','TASK-2','tckt_st_back','Backlog','2026-10-16T09:00:00+00:00') + '],"has_more":false}');

        Test.startTest();
        VeleiroTicketPull.Result r = VeleiroTicketPull.run();
        Test.stopTest();

        System.assertEquals(1, r.pulled, 'error=' + r.error);
        System.assert(m.lastGetUrl.contains('updated_since'), 'es incremental: ' + m.lastGetUrl);
        System.assert(m.lastGetUrl.contains('07%3A55') || m.lastGetUrl.contains('07:55'),
            'arranca 5 minutos antes de la marca: ' + m.lastGetUrl);
        System.assert(m.lastGetUrl.contains('project_id'), 'y acotada al proyecto habilitado');

        Datetime after = [SELECT Last_Pulled_At__c FROM Veleiro_Ticket_Project__c WHERE Id = :p.Id].Last_Pulled_At__c;
        System.assertEquals(Datetime.newInstanceGmt(2026, 10, 16, 9, 0, 0), after,
            'la marca avanza al updated_at mas reciente que se proceso');
    }

    // La primera corrida no tiene marca: pide todo y deja la marca escrita para la siguiente.
    @isTest
    static void theFirstRunTakesEverythingAndLeavesAWatermark() {
        Veleiro_Ticket_Project__c p = project('prjct_x', true);
        VeleiroTicketApiMock m = mockWith('{"data":[' + task('tckt_1','TASK-1','tckt_st_back','Backlog','2026-10-15T08:00:00+00:00') + '],"has_more":false}');

        Test.startTest();
        VeleiroTicketPull.run();
        Test.stopTest();

        System.assert(!m.lastGetUrl.contains('updated_since'), 'la primera trae todo: ' + m.lastGetUrl);
        System.assertNotEquals(null,
            [SELECT Last_Pulled_At__c FROM Veleiro_Ticket_Project__c WHERE Id = :p.Id].Last_Pulled_At__c);
    }

    @isTest
    static void aProjectThePartnerTurnedOffIsNotPulled() {
        project('prjct_x', false);
        mockWith('{"data":[' + task('tckt_1','TASK-1','tckt_st_back','Backlog','2026-10-15T08:00:00+00:00') + '],"has_more":false}');

        Test.startTest();
        VeleiroTicketPull.Result r = VeleiroTicketPull.run();
        Test.stopTest();

        System.assertEquals(0, r.projects);
        System.assertEquals(0, [SELECT COUNT() FROM Veleiro_Ticket__c]);
    }

    /**
     * Archivar en Veleiro no borra en Salesforce: se marca. Si desapareciera, el cliente
     * veria un ticket esfumarse sin explicacion.
     */
    @isTest
    static void archivedInVeleiroIsMarkedNotDeleted() {
        project('prjct_x', true);
        String archived = task('tckt_1','TASK-1','tckt_st_done','Done','2026-10-15T08:00:00+00:00')
            .replace('"is_archived":false', '"is_archived":true');
        mockWith('{"data":[' + archived + '],"has_more":false}');

        Test.startTest();
        VeleiroTicketPull.run();
        Test.stopTest();

        Veleiro_Ticket__c t = [SELECT Is_Archived__c, Work_Status__c FROM Veleiro_Ticket__c];
        System.assertEquals(true, t.Is_Archived__c);
        System.assertEquals('terminal', t.Work_Status__c, 'el tipo terminal se llama terminal, no done');
    }

    /**
     * Veleiro manda sobre sus campos, pero no sobre los de Salesforce: quien levanto el
     * ticket y desde que registro no viven en Veleiro y no se pueden perder en una bajada.
     */
    @isTest
    static void salesforceOwnFieldsSurviveThePull() {
        project('prjct_x', true);
        insert new Veleiro_Ticket__c(
            Title__c = 'Levantado desde Salesforce', Veleiro_Task_Id__c = 'tckt_1',
            Submitted_By_Name__c = 'Ana Pérez', Submitted_By_Email__c = 'ana@cliente.com',
            Description__c = 'Pasos para reproducir', SF_Record_Id__c = '001000000000abc',
            Source_URL__c = 'https://x.lightning.force.com/r/Account/001000000000abc/view'
        );
        mockWith('{"data":[' + task('tckt_1','TASK-1','tckt_st_prog','In Progress','2026-10-15T08:00:00+00:00') + '],"has_more":false}');

        Test.startTest();
        VeleiroTicketPull.run();
        Test.stopTest();

        Veleiro_Ticket__c t = [
            SELECT Submitted_By_Name__c, Description__c, SF_Record_Id__c, Source_URL__c, Work_Status__c
            FROM Veleiro_Ticket__c
        ];
        System.assertEquals('Ana Pérez', t.Submitted_By_Name__c, 'Veleiro no sabe quien lo levanto');
        System.assertEquals('Pasos para reproducir', t.Description__c,
            'la API todavia no devuelve description: no puede borrar la que ya teniamos');
        System.assertEquals('001000000000abc', t.SF_Record_Id__c);
        System.assertEquals('in_progress', t.Work_Status__c, 'y el estado si se actualiza');
    }

    @isTest
    static void withoutEnabledProjectsNothingHappens() {
        mockWith('{"data":[],"has_more":false}');
        Test.startTest();
        VeleiroTicketPull.Result r = VeleiroTicketPull.run();
        Test.stopTest();
        System.assertEquals(0, r.projects);
        System.assertEquals(0, r.pulled);
        System.assertEquals(null, r.error);
    }

    // Si Veleiro no contesta, la corrida lo reporta en vez de tronar.
    @isTest
    static void anApiFailureIsReportedNotThrown() {
        project('prjct_x', true);
        VeleiroTicketApiMock m = new VeleiroTicketApiMock();
        m.overrideStatus = 401;
        m.overrideBody = '{"error":{"code":"invalid_token"}}';
        Test.setMock(HttpCalloutMock.class, m);

        Test.startTest();
        VeleiroTicketPull.Result r = VeleiroTicketPull.run();
        Test.stopTest();

        System.assert(String.isNotBlank(r.error), 'el error queda a la vista');
        System.assertEquals(0, r.pulled);
    }

    @isTest
    static void theClockCanBeSetAndTurnedOff() {
        Test.startTest();
        VeleiroTicketPullJob.schedule('hourly');
        System.assertEquals(true, VeleiroTicketPullJob.isScheduled());
        VeleiroTicketPullJob.schedule('off');
        System.assertEquals(false, VeleiroTicketPullJob.isScheduled(), 'apagarlo deja de sonar');
        Test.stopTest();
    }

    @isTest
    static void theJobEnqueuesTheWork() {
        project('prjct_x', true);
        mockWith('{"data":[],"has_more":false}');
        Test.startTest();
        System.enqueueJob(new VeleiroTicketPullQueueable());
        Test.stopTest();
        System.assertEquals(0, [SELECT COUNT() FROM Veleiro_Ticket__c]);
    }

    @isTest
    static void theControllerExposesProjectsAndThePullButton() {
        project('prjct_x', true);
        mockWith('{"data":[],"has_more":false}');
        Test.startTest();
        System.assertEquals(1, VeleiroTicketController.listEnabledProjects().size());
        System.assertEquals(1, VeleiroTicketController.pullNow().projects);
        VeleiroTicketController.schedulePull('off');
        Test.stopTest();
    }

    // ================= varios proyectos =================

    private static String payload(String title, String projectId) {
        Map<String, Object> m = new Map<String, Object>{ 'title' => title };
        if (projectId != null) m.put('projectId', projectId);
        return JSON.serialize(m);
    }

    /**
     * El ticket va al proyecto que eligio quien lo levanto, no al unico de la config vieja.
     * Es lo que permite que un cliente tenga implementacion y postventa a la vez.
     */
    @isTest
    static void aTicketGoesToTheProjectTheUserPicked() {
        project('prjct_impl', true);
        Veleiro_Ticket_Project__c post = new Veleiro_Ticket_Project__c(
            Name = 'Postventa', Veleiro_Project_Id__c = 'prjct_post', Active__c = true,
            Veleiro_Client_Id__c = 'org_cliente'
        );
        insert post;
        Test.setMock(HttpCalloutMock.class, new VeleiroTicketApiMock());

        Test.startTest();
        Id id = VeleiroTicketController.createTicket(payload('Falla en postventa', 'prjct_post'));
        Test.stopTest();

        Veleiro_Ticket__c t = [SELECT Veleiro_Project_Id__c, Veleiro_Client_Id__c FROM Veleiro_Ticket__c WHERE Id = :id];
        System.assertEquals('prjct_post', t.Veleiro_Project_Id__c);
        System.assertEquals('org_cliente', t.Veleiro_Client_Id__c, 'el client sale del proyecto elegido');
    }

    // Un id que no este habilitado no se respeta: no se confia en lo que llega del navegador.
    @isTest
    static void aProjectTheUserIsNotAllowedToUseIsIgnored() {
        project('prjct_impl', true);
        Veleiro_Ticket_Project__c soloMirar = new Veleiro_Ticket_Project__c(
            Name = 'Solo mirar', Veleiro_Project_Id__c = 'prjct_watch', Active__c = true,
            Client_Can_Create__c = false
        );
        insert soloMirar;
        Test.setMock(HttpCalloutMock.class, new VeleiroTicketApiMock());

        Test.startTest();
        Id id = VeleiroTicketController.createTicket(payload('Intento colado', 'prjct_watch'));
        Test.stopTest();

        System.assertNotEquals('prjct_watch',
            [SELECT Veleiro_Project_Id__c FROM Veleiro_Ticket__c WHERE Id = :id].Veleiro_Project_Id__c,
            'un proyecto de solo lectura no acepta tickets nuevos');
    }

    // Con un solo proyecto habilitado no hay nada que elegir: se usa ese.
    @isTest
    static void withOneProjectTheUserDoesNotHaveToChoose() {
        project('prjct_impl', true);
        Test.setMock(HttpCalloutMock.class, new VeleiroTicketApiMock());

        Test.startTest();
        Id id = VeleiroTicketController.createTicket(payload('Sin elegir', null));
        Test.stopTest();

        System.assertEquals('prjct_impl',
            [SELECT Veleiro_Project_Id__c FROM Veleiro_Ticket__c WHERE Id = :id].Veleiro_Project_Id__c);
        System.assertEquals(1, VeleiroTicketController.listProjectsForIntake().size());
    }

    // El partner ve los proyectos de Veleiro con los que ya habilito marcados.
    @isTest
    static void thePartnerSeesVeleiroProjectsAndWhatIsAlreadyOn() {
        project('prjct_impl', true);
        VeleiroTicketApiMock m = new VeleiroTicketApiMock();
        m.projectsBody = '{"data":[' +
            '{"id":"prjct_impl","name":"Implementacion","client_id":"org_x","status":"active"},' +
            '{"id":"prjct_new","name":"Postventa","client_id":"org_x","status":"planning"}' +
            '],"has_more":false}';
        Test.setMock(HttpCalloutMock.class, m);

        Test.startTest();
        List<VeleiroTicketController.VeleiroProject> rows = VeleiroTicketController.listVeleiroProjects();
        Test.stopTest();

        System.assertEquals(2, rows.size());
        Map<String, Boolean> enabledById = new Map<String, Boolean>();
        for (VeleiroTicketController.VeleiroProject r : rows) enabledById.put(r.projectId, r.enabled);
        System.assertEquals(true, enabledById.get('prjct_impl'), 'el ya habilitado viene marcado');
        System.assertEquals(false, enabledById.get('prjct_new'), 'el otro no');
    }

    // Guardar habilita, y apagar no borra: los tickets ya traidos siguen ahi.
    @isTest
    static void savingEnablesAndTurningOffDoesNotDelete() {
        Test.startTest();
        VeleiroTicketController.saveEnabledProjects(JSON.serialize(new List<Object>{
            new Map<String, Object>{ 'projectId' => 'prjct_a', 'name' => 'Implementacion',
                                     'clientId' => 'org_x', 'enabled' => true, 'clientCanCreate' => true },
            new Map<String, Object>{ 'projectId' => 'prjct_b', 'name' => 'Postventa',
                                     'clientId' => 'org_x', 'enabled' => false, 'clientCanCreate' => true }
        }));
        Test.stopTest();

        System.assertEquals(2, [SELECT COUNT() FROM Veleiro_Ticket_Project__c], 'los dos quedan registrados');
        System.assertEquals(1, [SELECT COUNT() FROM Veleiro_Ticket_Project__c WHERE Active__c = true]);
        System.assertEquals(1, VeleiroTicketController.listEnabledProjects().size(),
            'solo el activo cuenta para la bajada');
    }
}
