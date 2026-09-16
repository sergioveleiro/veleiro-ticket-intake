@isTest
private class VeleiroTicketControllerTest {

    @testSetup
    static void setup() { VeleiroTicketApiMock.seedConfig(); }

    @isTest
    static void getSetupReturnsMapping() {
        Test.startTest();
        VeleiroTicketController.SetupInfo s = VeleiroTicketController.getSetup();
        Test.stopTest();
        System.assertEquals(true, s.connected);
        System.assertEquals('org_test', s.clientId);
        System.assertEquals('Colfondos', s.clientName);
        System.assertEquals('prjct_test', s.projectId);
    }

    @isTest
    static void saveMappingUpserts() {
        Test.startTest();
        VeleiroTicketController.saveMapping('org_new', 'New Client', 'prj_new', 'New Project');
        Test.stopTest();
        Veleiro_Ticket_Config__c c = Veleiro_Ticket_Config__c.getOrgDefaults();
        System.assertEquals('org_new', c.Veleiro_Client_Id__c);
        System.assertEquals('New Client', c.Veleiro_Client_Name__c);
        System.assertEquals('prj_new', c.Veleiro_Project_Id__c);
    }

    @isTest
    static void saveMappingBlankProjectClears() {
        Test.startTest();
        VeleiroTicketController.saveMapping('org_new', 'New Client', '', '');
        Test.stopTest();
        Veleiro_Ticket_Config__c c = Veleiro_Ticket_Config__c.getOrgDefaults();
        System.assertEquals(null, c.Veleiro_Project_Id__c);
    }

    @isTest
    static void createTicketInsertsAttachesAndSends() {
        VeleiroTicketApiMock mock = new VeleiroTicketApiMock();
        Test.setMock(HttpCalloutMock.class, mock);
        String b64 = EncodingUtil.base64Encode(Blob.valueOf('fake-image-bytes'));
        Map<String, Object> payload = new Map<String, Object>{
            'title' => 'Website roto',
            'description' => 'No carga',
            'ticketType' => 'Bug',
            'priority' => 'Urgent',
            'sourceUrl' => 'https://x.lightning.force.com/lightning/r/Account/001000000000abc/view',
            'sfObject' => 'Account',
            'sfRecordId' => '001000000000abc',
            'files' => new List<Object>{ new Map<String, Object>{ 'name' => 'shot.png', 'base64' => b64, 'contentType' => 'image/png' } }
        };
        Test.startTest();
        Id ticketId = VeleiroTicketController.createTicket(JSON.serialize(payload));
        Test.stopTest(); // corre el Queueable con el mock -> push a Veleiro

        Veleiro_Ticket__c t = [
            SELECT Status__c, Veleiro_Task_Id__c, Title__c, Source_URL__c, Submitted_By_Name__c
            FROM Veleiro_Ticket__c WHERE Id = :ticketId
        ];
        System.assertEquals('Website roto', t.Title__c);
        System.assertEquals('Sent', t.Status__c, 'el push async corrio en stopTest');
        System.assertEquals('task_test', t.Veleiro_Task_Id__c);
        System.assert(String.isNotBlank(t.Submitted_By_Name__c), 'guarda quien lo levanto');

        Integer links = [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :ticketId];
        System.assertEquals(1, links, 'el adjunto quedo ligado al ticket');
    }

    // Con el kit, un ticket desde un registro vinculado va a su client (campos estandar en el test).
    private static Veleiro_Ticket__c ticketFrom(Id recordId) {
        VeleiroTicketRouting.clientField = 'AccountNumber';
        VeleiroTicketRouting.projectField = 'NextStep';
        Id ticketId = VeleiroTicketController.createTicket(JSON.serialize(new Map<String, Object>{
            'title' => 'Desde registro', 'sfRecordId' => recordId
        }));
        return [SELECT Veleiro_Client_Id__c, Veleiro_Project_Id__c FROM Veleiro_Ticket__c WHERE Id = :ticketId];
    }

    @isTest
    static void createTicketRoutesToLinkedClient() {
        Account a = new Account(Name = 'Linked', AccountNumber = 'org_linked');
        insert a;
        Veleiro_Ticket__c t = ticketFrom(a.Id);
        System.assertEquals('org_linked', t.Veleiro_Client_Id__c);
        System.assertEquals(null, t.Veleiro_Project_Id__c, 'el project configurado es de otro client');
    }

    @isTest
    static void createTicketKeepsConfiguredProjectForSameClient() {
        Account a = new Account(Name = 'Configured', AccountNumber = 'org_test');
        insert a;
        Veleiro_Ticket__c t = ticketFrom(a.Id);
        System.assertEquals('org_test', t.Veleiro_Client_Id__c);
        System.assertEquals('prjct_test', t.Veleiro_Project_Id__c);
    }

    @isTest
    static void createTicketUsesDefaultWhenUnlinked() {
        Account a = new Account(Name = 'Unlinked');
        insert a;
        Veleiro_Ticket__c t = ticketFrom(a.Id);
        System.assertEquals('org_test', t.Veleiro_Client_Id__c);
        System.assertEquals('prjct_test', t.Veleiro_Project_Id__c);
    }

    @isTest
    static void createTicketRequiresTitle() {
        Boolean threw = false;
        Test.startTest();
        try {
            VeleiroTicketController.createTicket(JSON.serialize(new Map<String, Object>{ 'description' => 'x' }));
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();
        System.assertEquals(true, threw, 'sin titulo -> error');
    }

    @isTest
    static void listClientsAndProjectsViaController() {
        VeleiroTicketApiMock mock = new VeleiroTicketApiMock();
        mock.clientsBody = '{"data":[{"id":"org_test","name":"Colfondos"}],"has_more":false}';
        mock.projectsBody = '{"data":[{"id":"prjct_test","name":"Impl","client_id":"org_test"}],"has_more":false}';
        Test.setMock(HttpCalloutMock.class, mock);
        Test.startTest();
        System.assertEquals(1, VeleiroTicketController.listClients().size());
        System.assertEquals(1, VeleiroTicketController.listProjects('org_test').size());
        Test.stopTest();
    }
}
