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
    // El kit puede estar instalado como paquete administrado: ahi sus campos llevan prefijo.
    private static final String KIT_NAMESPACE = 'veleiro__';

    // Nunca truena: ante cualquier problema devuelve null y el ticket usa el default.
    public static Target forRecord(String recordId) {
        try {
            Id rid = Id.valueOf(recordId);
            String obj = rid.getSobjectType().getDescribe().getName();
            String clientApi = resolveField('Account', clientField);
            if (clientApi == null) return null; // kit no instalado

            String clientExpr;
            if (obj == 'Account') {
                clientExpr = clientApi;
            } else if (hasField(obj, 'AccountId')) {
                clientExpr = 'Account.' + clientApi;
            } else {
                return null;
            }
            String projectApi = (obj == 'Opportunity') ? resolveField('Opportunity', projectField) : null;
            String soql = 'SELECT ' + clientExpr + (projectApi != null ? ', ' + projectApi : '') +
                          ' FROM ' + obj + ' WHERE Id = :rid';
            List<SObject> rows = Database.query(soql);
            if (rows.isEmpty()) return null;

            SObject source = obj == 'Account' ? rows[0] : rows[0].getSObject('Account');
            return choose(
                source == null ? null : (String) source.get(clientApi),
                projectApi != null ? (String) rows[0].get(projectApi) : null
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

    // Nombre real del campo del kit: con prefijo si esta instalado como paquete administrado,
    // sin prefijo si esta desplegado desde el codigo fuente. null si el kit no esta.
    private static String resolveField(String obj, String field) {
        if (hasField(obj, KIT_NAMESPACE + field)) return KIT_NAMESPACE + field;
        if (hasField(obj, field)) return field;
        return null;
    }

    private static Boolean hasField(String obj, String field) {
        Schema.SObjectType type = Schema.getGlobalDescribe().get(obj);
        return type != null && type.getDescribe().fields.getMap().containsKey(field.toLowerCase());
    }
}
