/**
 * Empuja un Veleiro_Ticket__c a Veleiro en su propia transaccion (callout permitido).
 * Se encola despues del insert del ticket para no chocar con "uncommitted work + callout".
 */
public class VeleiroTicketPushQueueable implements Queueable, Database.AllowsCallouts {
    private final Id ticketId;
    public VeleiroTicketPushQueueable(Id ticketId) {
        this.ticketId = ticketId;
    }
    public void execute(QueueableContext ctx) {
        VeleiroTicketService.pushTicket(ticketId);
    }
}
