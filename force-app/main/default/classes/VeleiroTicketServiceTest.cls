@isTest
private class VeleiroTicketServiceTest {

    @testSetup
    static void setup() { VeleiroApiMock.seedConfig(); }

    private static Veleiro_Ticket__c newTicket(Boolean withDue) {
        Veleiro_Ticket__c t = new Veleiro_Ticket__c(
            Title__c = 'No puedo guardar la cuenta',
            Description__c = 'Sale un error al guardar',
            Ticket_Type__c = 'Bug',
            Priority__c = 'High',
            Source_URL__c = 'https://x.lightning.force.com/lightning/r/Account/001000000000001/view',
            SF_Object__c = 'Account',
            SF_Record_Id__c = '001000000000001',
            Status__c = 'New',
            Veleiro_Client_Id__c = 'org_test',
            Veleiro_Project_Id__c = 'prjct_test'
        );
        if (withDue) t.Due_Date__c = Date.today().addDays(7);
        insert t;
        return t;
    }

    @isTest
    static void pushCreatesTaskAndMatch() {
        Veleiro_Ticket__c t = newTicket(false);
        VeleiroApiMock mock = new VeleiroApiMock();
        Test.setMock(HttpCalloutMock.class, mock);
        Test.startTest();
        VeleiroTicketService.pushTicket(t.Id);
        Test.stopTest();

        Veleiro_Ticket__c after = [
            SELECT Status__c, Veleiro_Task_Id__c, Veleiro_Task_Key__c, Veleiro_Status__c, Veleiro_Task_Url__c
            FROM Veleiro_Ticket__c WHERE Id = :t.Id
        ];
        System.assertEquals('Sent', after.Status__c);
        System.assertEquals('task_test', after.Veleiro_Task_Id__c);
        System.assertEquals('CLF-1', after.Veleiro_Task_Key__c);
        System.assert(after.Veleiro_Task_Url__c.contains('/organizations/org_test'), 'link a Veleiro');

        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(mock.lastPostBody);
        System.assertEquals('org_test', body.get('client_id'));
        Map<String, Object> af = (Map<String, Object>) body.get('additional_fields');
        System.assertEquals('Account', af.get('sf_object'));
        System.assert(String.valueOf(af.get('sf_record_url')).contains('/Account/'), 'la URL viaja en additional_fields');
    }

    @isTest
    static void pushWithDueDatePatches() {
        Veleiro_Ticket__c t = newTicket(true);
        VeleiroApiMock mock = new VeleiroApiMock();
        Test.setMock(HttpCalloutMock.class, mock);
        Test.startTest();
        VeleiroTicketService.pushTicket(t.Id);
        Test.stopTest();

        Veleiro_Ticket__c after = [SELECT Status__c, Veleiro_Version__c FROM Veleiro_Ticket__c WHERE Id = :t.Id];
        System.assertEquals('Sent', after.Status__c);
        System.assertEquals(2, after.Veleiro_Version__c, 'la version subio con el PATCH del due_date');
        System.assert(mock.lastPatchBody != null && mock.lastPatchBody.contains('due_date'), 'se mando el due_date via PATCH');
    }

    @isTest
    static void pushRecordsErrorOnInsufficientScope() {
        Veleiro_Ticket__c t = newTicket(false);
        VeleiroApiMock mock = new VeleiroApiMock();
        mock.overrideStatus = 403;
        mock.overrideBody = '{"error":{"code":"insufficient_scope","message":"task scope required"}}';
        Test.setMock(HttpCalloutMock.class, mock);
        Test.startTest();
        VeleiroTicketService.pushTicket(t.Id);
        Test.stopTest();

        Veleiro_Ticket__c after = [SELECT Status__c, Sync_Error__c FROM Veleiro_Ticket__c WHERE Id = :t.Id];
        System.assertEquals('Error', after.Status__c);
        System.assert(after.Sync_Error__c.contains('insufficient_scope'), 'guarda el error');
    }

    @isTest
    static void listsClientsAndProjects() {
        VeleiroApiMock mock = new VeleiroApiMock();
        mock.clientsBody = '{"data":[{"id":"org_test","name":"Colfondos","is_archived":false},{"id":"org_arch","name":"Old","is_archived":true}],"has_more":false}';
        mock.projectsBody = '{"data":[{"id":"prjct_test","name":"Implementation","client_id":"org_test","is_archived":false},{"id":"prjct_x","name":"Otro","client_id":"org_other","is_archived":false}],"has_more":false}';
        Test.setMock(HttpCalloutMock.class, mock);
        Test.startTest();
        List<VeleiroTicketService.Option> clients = VeleiroTicketService.listClients();
        List<VeleiroTicketService.Option> projects = VeleiroTicketService.listProjects('org_test');
        Test.stopTest();

        System.assertEquals(1, clients.size(), 'archivado excluido');
        System.assertEquals('Colfondos', clients[0].name);
        System.assertEquals(1, projects.size(), 'solo los del client');
        System.assertEquals('Implementation', projects[0].name);
    }
}
