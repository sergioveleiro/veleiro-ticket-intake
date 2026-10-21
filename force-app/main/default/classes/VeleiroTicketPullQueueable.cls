/**
 * Corre la bajada fuera del job programado.
 *
 * Apex agendado no puede hacer callouts: por eso el Schedulable encola esto y el trabajo
 * de verdad ocurre aqui. Mismo patron que usa el kit de ventas.
 */
public with sharing class VeleiroTicketPullQueueable implements Queueable, Database.AllowsCallouts {
    public void execute(QueueableContext qc) {
        VeleiroTicketPull.Result r = VeleiroTicketPull.run();
        if (String.isNotBlank(r.error)) {
            System.debug(LoggingLevel.ERROR, 'Bajada de tickets: ' + r.error);
        }
    }
}
