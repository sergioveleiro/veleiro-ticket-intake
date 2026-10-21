/**
 * El catalogo de estados de Veleiro, que es lo que hace posible mover un ticket desde Salesforce.
 *
 * Cada partner nombra sus estados como quiere ("Input Required", "UAT"), pero todos declaran uno
 * de cinco state_type. El Kanban agrupa por el tipo (Work_Status__c) porque es lo unico que se
 * puede empaquetar; para escribir en Veleiro hace falta el id del estado concreto, y eso solo
 * se sabe preguntando. Se pregunta una vez por transaccion y se guarda en memoria.
 *
 * Cuando dos estados comparten tipo (un partner tenia "Input Required" y "Action Needed", ambos
 * blocked) la eleccion tiene que ser estable, o el mismo arrastre caeria en un estado distinto
 * cada vez: se ordena por nombre y gana el primero.
 */
public with sharing class VeleiroTicketStates {

    public class State {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String stateType;
    }

    @TestVisible private static List<State> cached;

    public static List<State> all() {
        if (cached != null) return cached;
        List<State> out = new List<State>();
        for (Object o : VeleiroTicketApiClient.listAll('/tasks/states', null)) {
            Map<String, Object> raw = (Map<String, Object>) o;
            State s = new State();
            s.id = (String) raw.get('id');
            s.name = (String) raw.get('name');
            s.stateType = (String) raw.get('state_type');
            if (String.isBlank(s.name)) s.name = s.stateType;
            if (String.isNotBlank(s.id)) out.add(s);
        }
        cached = out;
        return cached;
    }

    /**
     * El estado al que mandar un ticket que pasa a este tipo. null si Veleiro no tiene ninguno
     * de ese tipo: ahi no hay nada que hacer y quien llama avisa en vez de inventar.
     */
    public static State forType(String stateType) {
        if (String.isBlank(stateType)) return null;
        List<State> matches = new List<State>();
        for (State s : all()) {
            if (stateType.equalsIgnoreCase(s.stateType)) matches.add(s);
        }
        if (matches.isEmpty()) return null;
        State best = matches[0];
        for (State s : matches) {
            if (s.name != null && best.name != null && s.name.compareTo(best.name) < 0) best = s;
        }
        return best;
    }
}
