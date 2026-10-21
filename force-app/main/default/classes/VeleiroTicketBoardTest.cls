/**
 * La vista avanzada y el movimiento de etapa.
 *
 * Lo que de verdad importa probar aqui es que un movimiento NO deja rastro local cuando Veleiro
 * lo rechaza: ese era el bug de la version anterior (el campo cambiaba y la siguiente bajada lo
 * borraba), y es la clase de cosa que un test verde por el motivo equivocado tapa muy bien.
 */
@isTest
private class VeleiroTicketBoardTest {

    private static final String STATES =
        '{"data":[' +
        '{"id":"st_new","name":"Backlog","state_type":"initial"},' +
        '{"id":"st_doing","name":"In Progress","state_type":"in_progress"},' +
        '{"id":"st_uat","name":"UAT","state_type":"review"},' +
        '{"id":"st_action","name":"Action Needed","state_type":"blocked"},' +
        '{"id":"st_input","name":"Input Required","state_type":"blocked"},' +
        '{"id":"st_done","name":"Done","state_type":"terminal"}' +
        ']}';

    @testSetup
    static void setup() {
        VeleiroTicketApiMock.seedConfig();
        insert new Veleiro_Ticket_Project__c(
            Name = 'Implementation', Veleiro_Project_Id__c = 'prjct_test',
            Veleiro_Client_Id__c = 'org_test', Active__c = true, Client_Can_Create__c = true
        );
    }

    private static Veleiro_Ticket__c ticket(String stage, String statusId) {
        Veleiro_Ticket__c t = new Veleiro_Ticket__c(
            Title__c = 'Algo que arreglar',
            Priority__c = 'High',
            Ticket_Type__c = 'Task',
            Work_Status__c = stage,
            Veleiro_Status__c = 'Backlog',
            Veleiro_Status_Id__c = statusId,
            Veleiro_Task_Id__c = 'task_1',
            Veleiro_Task_Key__c = 'CLF-1',
            Veleiro_Project_Id__c = 'prjct_test',
            Veleiro_Project_Name__c = 'Implementation',
            Assignees__c = 'Ana, Beto',
            Labels__c = 'urgente, api',
            Veleiro_Version__c = 3
        );
        insert t;
        return t;
    }

    // Los mismos estados del mock, pero sin pasar por la red.
    private static List<VeleiroTicketStates.State> seededStates() {
        List<VeleiroTicketStates.State> out = new List<VeleiroTicketStates.State>();
        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(STATES);
        for (Object o : (List<Object>) body.get('data')) {
            Map<String, Object> raw = (Map<String, Object>) o;
            VeleiroTicketStates.State s = new VeleiroTicketStates.State();
            s.id = (String) raw.get('id');
            s.name = (String) raw.get('name');
            s.stateType = (String) raw.get('state_type');
            out.add(s);
        }
        return out;
    }

    private static VeleiroTicketApiMock mockWithStates() {
        VeleiroTicketApiMock m = new VeleiroTicketApiMock();
        m.statesBody = STATES;
        Test.setMock(HttpCalloutMock.class, m);
        return m;
    }

    @isTest
    static void theBoardServesCardsFiltersAndTheBoardLink() {
        ticket('in_progress', 'st_doing');
        Test.startTest();
        VeleiroTicketBoardController.Board b = VeleiroTicketBoardController.load();
        Test.stopTest();

        System.assertEquals(5, b.stages.size(), 'cinco columnas, el flujo completo');
        System.assertEquals('initial', b.stages[0], 'la primera columna es lo recien llegado');
        System.assertEquals(1, b.cards.size());
        VeleiroTicketBoardController.Card c = b.cards[0];
        System.assertEquals('in_progress', c.stage);
        System.assertEquals(2, c.labels.size(), 'las etiquetas llegan partidas, no como un texto');
        System.assertEquals(new List<String>{'Ana', 'Beto'}, b.assignees, 'el filtro de gente sale de los tickets');
        System.assertEquals(new List<String>{'Implementation'}, b.projects);
        System.assertEquals(false, b.truncated);
        System.assert(b.boardUrl.endsWith('/projects/prjct_test/'), 'link al tablero: ' + b.boardUrl);
    }

    @isTest
    static void aTicketWithoutStageLandsInTheFirstColumn() {
        // Un ticket recien levantado todavia no bajo de Veleiro: no tiene state_type.
        Veleiro_Ticket__c t = ticket(null, null);
        t.Work_Status__c = null;
        update t;

        Test.startTest();
        VeleiroTicketBoardController.Board b = VeleiroTicketBoardController.load();
        Test.stopTest();
        System.assertEquals('initial', b.cards[0].stage, 'sin etapa, se muestra como nuevo');
    }

    @isTest
    static void theBoardSaysWhenItHitTheCap() {
        ticket('initial', 'st_new');
        VeleiroTicketBoardController.maxRows = 1;
        Test.startTest();
        VeleiroTicketBoardController.Board b = VeleiroTicketBoardController.load();
        Test.stopTest();
        System.assertEquals(true, b.truncated, 'al tope, la vista lo dice en vez de callarse');
    }

    @isTest
    static void movingWritesVeleiroFirstAndThenSalesforce() {
        Veleiro_Ticket__c t = ticket('initial', 'st_new');
        VeleiroTicketApiMock m = mockWithStates();
        m.singleTaskBody = '{"data":{"id":"task_1","status":"UAT","status_id":"st_uat","version":4}}';

        Test.startTest();
        VeleiroTicketMove.Result r = VeleiroTicketBoardController.move(t.Id, 'review');
        Test.stopTest();

        System.assertEquals(true, r.moved, 'error: ' + r.error);
        System.assertEquals('review', r.stage);
        System.assert(m.lastPatchBody.contains('st_uat'), 'se manda el id del estado, no el tipo: ' + m.lastPatchBody);

        Veleiro_Ticket__c saved = [SELECT Work_Status__c, Veleiro_Status__c, Veleiro_Status_Id__c, Veleiro_Version__c
                                   FROM Veleiro_Ticket__c WHERE Id = :t.Id];
        System.assertEquals('review', saved.Work_Status__c);
        System.assertEquals('UAT', saved.Veleiro_Status__c, 'queda el nombre que contesto Veleiro');
        System.assertEquals('st_uat', saved.Veleiro_Status_Id__c);
        System.assertEquals(4, saved.Veleiro_Version__c, 'la version nueva evita un 409 en el proximo cambio');
    }

    @isTest
    static void aRejectedMoveLeavesNoTraceInSalesforce() {
        Veleiro_Ticket__c t = ticket('initial', 'st_new');
        VeleiroTicketApiMock m = mockWithStates();
        // Los estados se siembran en memoria en vez de pedirlos: un callout despues del insert
        // seria "uncommitted work pending", que es un fallo del test y no del codigo.
        VeleiroTicketStates.cached = seededStates();
        m.overrideStatus = 409;
        m.overrideBody = '{"error":{"code":"version_conflict","message":"stale","detail":{"current_version":9}}}';

        Test.startTest();
        VeleiroTicketMove.Result r = VeleiroTicketBoardController.move(t.Id, 'terminal');
        Test.stopTest();

        System.assertEquals(false, r.moved);
        System.assertEquals('version_conflict', r.code, 'se ramifica por code, no por mensaje');
        Veleiro_Ticket__c saved = [SELECT Work_Status__c FROM Veleiro_Ticket__c WHERE Id = :t.Id];
        System.assertEquals('initial', saved.Work_Status__c, 'si Veleiro dice no, aqui no cambia nada');
    }

    @isTest
    static void thePartnerCanCloseAStageToTheClient() {
        Veleiro_Ticket__c t = ticket('review', 'st_uat');
        Veleiro_Ticket_Project__c p = [SELECT Id FROM Veleiro_Ticket_Project__c LIMIT 1];
        // El partner deja solo UAT y cerrar; bloquear no es del cliente.
        p.Client_Allowed_States__c = 'UAT\nterminal';
        update p;
        mockWithStates();

        Test.startTest();
        VeleiroTicketMove.Result blocked = VeleiroTicketBoardController.move(t.Id, 'blocked');
        VeleiroTicketMove.Result closing = VeleiroTicketBoardController.move(t.Id, 'terminal');
        Test.stopTest();

        System.assertEquals(false, blocked.moved, 'bloquear no estaba en la lista');
        System.assertEquals('not_allowed', blocked.code);
        System.assertEquals(true, closing.moved, 'cerrar si, y por tipo: ' + closing.error);
    }

    @isTest
    static void aTicketThatNeverReachedVeleiroCannotMoveThere() {
        Veleiro_Ticket__c t = ticket('initial', null);
        t.Veleiro_Task_Id__c = null;
        update t;
        mockWithStates();

        Test.startTest();
        VeleiroTicketMove.Result r = VeleiroTicketBoardController.move(t.Id, 'in_progress');
        Test.stopTest();
        System.assertEquals(false, r.moved);
        System.assertEquals('not_in_veleiro', r.code);
    }

    @isTest
    static void withTwoStatesOfTheSameTypeTheChoiceIsStable() {
        VeleiroTicketStates.cached = null;
        mockWithStates();
        Test.startTest();
        VeleiroTicketStates.State first = VeleiroTicketStates.forType('blocked');
        VeleiroTicketStates.State again = VeleiroTicketStates.forType('blocked');
        VeleiroTicketStates.State none = VeleiroTicketStates.forType('no_existe');
        Test.stopTest();
        // Un partner real tenia "Input Required" y "Action Needed", los dos blocked: el mismo
        // arrastre tiene que caer siempre en el mismo, o el ticket viaja solo.
        System.assertEquals('st_action', first.id, 'gana el primero por nombre');
        System.assertEquals(first.id, again.id, 'y la segunda vez contesta igual');
        System.assertEquals(null, none, 'un tipo que Veleiro no tiene no se inventa');
    }

    @isTest
    static void movingToTheStateItIsAlreadyInCostsNothing() {
        Veleiro_Ticket__c t = ticket('review', 'st_uat');
        VeleiroTicketApiMock m = mockWithStates();

        Test.startTest();
        VeleiroTicketMove.Result r = VeleiroTicketBoardController.move(t.Id, 'review');
        Test.stopTest();

        System.assertEquals(true, r.moved);
        System.assertEquals(null, m.lastPatchBody, 'no se gasta una escritura en algo que ya era asi');
    }
}
