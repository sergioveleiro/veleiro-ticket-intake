/**
 * Ruteo opcional con veleiro-salesforce-kit (sin depender de el).
 *
 * Si el kit esta instalado, los registros ya vinculados guardan su client/project de Veleiro:
 *   Account.Veleiro_Client_Id__c, Opportunity.Veleiro_Project_Id__c.
 * Un ticket levantado desde ese registro (o desde uno con AccountId: Contact, Case, ...) se
 * manda a ese client/project en vez del default configurado. Los campos se leen por describe
 * y SOQL dinamico, asi que sin el kit este codigo compila, se instala y simplemente no rutea.
 */
public with sharing class VeleiroTicketRouting {

    public class Target {
        public String clientId;
        public String projectId;
    }

    // Campos del kit. @TestVisible para que los tests usen campos estandar en orgs sin el kit.
    @TestVisible private static String clientField = 'Veleiro_Client_Id__c';
    @TestVisible private static String projectField = 'Veleiro_Project_Id__c';

    // Nunca truena: ante cualquier problema devuelve null y el ticket usa el default.
    public static Target forRecord(String recordId) {
        try {
            Id rid = Id.valueOf(recordId);
            String obj = rid.getSobjectType().getDescribe().getName();
            if (!hasField('Account', clientField)) return null; // kit no instalado

            String clientExpr;
            if (obj == 'Account') {
                clientExpr = clientField;
            } else if (hasField(obj, 'AccountId')) {
                clientExpr = 'Account.' + clientField;
            } else {
                return null;
            }
            Boolean withProject = obj == 'Opportunity' && hasField('Opportunity', projectField);
            String soql = 'SELECT ' + clientExpr + (withProject ? ', ' + projectField : '') +
                          ' FROM ' + obj + ' WHERE Id = :rid';
            List<SObject> rows = Database.query(soql);
            if (rows.isEmpty()) return null;

            SObject source = obj == 'Account' ? rows[0] : rows[0].getSObject('Account');
            return choose(
                source == null ? null : (String) source.get(clientField),
                withProject ? (String) rows[0].get(projectField) : null
            );
        } catch (Exception e) {
            return null;
        }
    }

    // Sin client vinculado no hay ruta: un project sin su client no alcanza para la task.
    @TestVisible
    private static Target choose(String clientId, String projectId) {
        if (String.isBlank(clientId)) return null;
        Target t = new Target();
        t.clientId = clientId;
        t.projectId = String.isBlank(projectId) ? null : projectId;
        return t;
    }

    private static Boolean hasField(String obj, String field) {
        Schema.SObjectType type = Schema.getGlobalDescribe().get(obj);
        return type != null && type.getDescribe().fields.getMap().containsKey(field.toLowerCase());
    }
}
