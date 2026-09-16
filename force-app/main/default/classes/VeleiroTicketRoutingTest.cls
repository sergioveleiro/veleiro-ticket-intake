@isTest
private class VeleiroTicketRoutingTest {

    // Campos estandar en lugar de los del kit: los tests corren igual con o sin el kit instalado.
    private static void useStandardFields() {
        VeleiroTicketRouting.clientField = 'AccountNumber';
        VeleiroTicketRouting.projectField = 'NextStep';
    }

    @isTest
    static void accountRoutesToItsClient() {
        useStandardFields();
        Account a = new Account(Name = 'Linked', AccountNumber = 'org_linked');
        insert a;

        VeleiroTicketRouting.Target t = VeleiroTicketRouting.forRecord(a.Id);
        System.assertEquals('org_linked', t.clientId);
        System.assertEquals(null, t.projectId);
    }

    @isTest
    static void opportunityRoutesToProjectAndClient() {
        useStandardFields();
        Account a = new Account(Name = 'Linked', AccountNumber = 'org_linked');
        insert a;
        Opportunity o = new Opportunity(Name = 'Deal', StageName = 'Prospecting',
            CloseDate = Date.today(), AccountId = a.Id, NextStep = 'prjct_linked');
        insert o;

        VeleiroTicketRouting.Target t = VeleiroTicketRouting.forRecord(o.Id);
        System.assertEquals('org_linked', t.clientId);
        System.assertEquals('prjct_linked', t.projectId);
    }

    @isTest
    static void contactRoutesThroughItsAccount() {
        useStandardFields();
        Account a = new Account(Name = 'Linked', AccountNumber = 'org_linked');
        insert a;
        Contact c = new Contact(LastName = 'Doe', AccountId = a.Id);
        insert c;

        System.assertEquals('org_linked', VeleiroTicketRouting.forRecord(c.Id).clientId);
    }

    @isTest
    static void unlinkedAccountHasNoRoute() {
        useStandardFields();
        Account a = new Account(Name = 'Unlinked');
        insert a;
        System.assertEquals(null, VeleiroTicketRouting.forRecord(a.Id));
    }

    @isTest
    static void noRouteWithoutKitOrUsableRecord() {
        useStandardFields();
        System.assertEquals(null, VeleiroTicketRouting.forRecord(null));
        System.assertEquals(null, VeleiroTicketRouting.forRecord('not-an-id'));
        System.assertEquals(null, VeleiroTicketRouting.forRecord(UserInfo.getUserId()), 'User no tiene Account');

        VeleiroTicketRouting.clientField = 'Field_That_Does_Not_Exist__c';
        Account a = new Account(Name = 'Any');
        insert a;
        System.assertEquals(null, VeleiroTicketRouting.forRecord(a.Id), 'sin el kit no rutea');
    }

    @isTest
    static void projectAloneIsNotARoute() {
        System.assertEquals(null, VeleiroTicketRouting.choose(null, 'prjct_x'));
        System.assertEquals(null, VeleiroTicketRouting.choose('org_x', ' ').projectId);
    }
}
