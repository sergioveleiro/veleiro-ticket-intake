/**
 * El reloj de la bajada. Veleiro no tiene webhooks, asi que alguien tiene que preguntar.
 * Cada hora es el ritmo por defecto; el boton "Traer cambios" existe para cuando una hora
 * es demasiado.
 */
global class VeleiroTicketPullJob implements Schedulable {

    global static final String JOB_NAME = 'Veleiro Ticket Pull';

    global void execute(SchedulableContext sc) {
        System.enqueueJob(new VeleiroTicketPullQueueable());
    }

    // Deja un solo job vivo: reprogramar no debe dejar dos relojes sonando.
    public static void schedule(String frequency) {
        for (CronTrigger ct : [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name = :JOB_NAME]) {
            System.abortJob(ct.Id);
        }
        if (frequency == 'off') return;
        String cron = (frequency == 'daily') ? '0 0 6 * * ?' : '0 0 * * * ?';   // diario 6am | cada hora
        System.schedule(JOB_NAME, cron, new VeleiroTicketPullJob());
    }

    public static Boolean isScheduled() {
        return [SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.Name = :JOB_NAME] > 0;
    }
}
