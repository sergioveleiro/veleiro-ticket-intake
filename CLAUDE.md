# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`veleiro-ticket-intake`: a small Salesforce DX add-on (no namespace, API 62.0, metadata only, no build step) that lets end users **raise a ticket from anywhere in Salesforce** and mirrors it as a **task in Veleiro**. It is a **separate product** from `veleiro-salesforce-kit` (the partner sales-motion integration, sibling folder).

## Independence from the kit (non-negotiable)

Both packages can be installed in the same org (e.g. Veleiro Main), in any order. Deploying one must never overwrite the other, so **every component name here is ticket-specific**:
- Apex: `VeleiroTicket*` (HTTP client is `VeleiroTicketApiClient`, test mock is `VeleiroTicketApiMock`).
- LWC: `veleiroTicket*` (branding is `c/veleiroTicketBrand`).
- Config: `Veleiro_Ticket_Config__c`, its own token and environment.
- Named Credentials: `Veleiro_Ticket_API` / `Veleiro_Ticket_API_Beta`.

Never add a component whose API name exists in the kit (`VeleiroApi*`, `Veleiro_Config__c`, `Veleiro_API*`, `veleiroBrand`, …). Never reference kit code statically.

**Optional kit integration is data-only:** `VeleiroTicketRouting` checks by describe whether `Account.Veleiro_Client_Id__c` / `Opportunity.Veleiro_Project_Id__c` exist and, if the source record is linked, files the ticket under that client/project. Without the kit it returns null and the configured default applies. Its tests swap the field names for standard fields (`AccountNumber`, `NextStep`) so they pass with or without the kit.

## Architecture

- `Veleiro_Ticket__c`: the local ticket. Mirrors the Veleiro task fields the API supports and holds the match (`Veleiro_Task_Id__c` external id, key, version, status, `Sync_Error__c`).
- `Veleiro_Ticket_Config__c`: Hierarchy custom setting, **must stay `Public`** (Protected fails on production deploys). Token + base URL + default Veleiro `client_id`/`project_id`. The token is data, never in git.
- `VeleiroTicketApiClient`: the only HTTP touchpoint. No trailing slash, `{data,has_more,next_cursor}` envelope, branch on `error.code` (never message), 409 `version_conflict` carries `detail.current_version`.
- `VeleiroTicketService`: `listClients`/`listProjects` (setup dropdowns) and `pushTicket` (create task + optional `due_date` PATCH; records Sent/Error on the ticket, never throws).
- `VeleiroTicketController`: `@AuraEnabled` surface. `createTicket` takes a **JSON string** and `JSON.deserialize`s it (avoids the LWC→Apex `List<CustomClass>` null-marshaling bug), applies routing, inserts, then enqueues `VeleiroTicketPushQueueable` so the callout runs outside the DML transaction.
- `veleiroTicketIntake` LWC: utility bar + record page. URL via `window.location.href`; record/object via `CurrentPageReference` or URL parse. Files read client-side to base64.
- `veleiroTicketConfig` LWC: connect (token, Production/Beta) + map default client/project.

## Guards (don't remove them)

- **A failing attachment must never cost the ticket.** `createTicket` saves the ticket first and attaches afterwards inside a try/catch; files over `maxFileBytes` (4 MB) are skipped and named in `Attachment_Note__c`, a field separate from `Sync_Error__c` so a successful push doesn't wipe the warning.
- **`retryPush` resends a failed ticket** instead of making the user file a new one; it clears the error and re-enqueues the same record.
- **Tests never insert Contacts or Cases.** A partner org rejected Contact inserts with its own validation rule and rolled back a whole deploy of the sibling kit; Apex tests can't bypass validation rules. Use Account and Opportunity only.

## Hard facts (don't relearn these)

- The Veleiro API has **no file upload** endpoint. Screenshots stay in Salesforce Files; only context goes to Veleiro via `additional_fields`.
- Task create needs only `title`. `due_date`/`start_date`/`status` are PATCH-only.
- `ticket_type` must be one of epic, story, task, decision, approval, review, deliverable, action_item, milestone, subtask; `priority` one of low, medium, high, critical (`urgent` → critical). `VeleiroTicketService` normalizes.
- The token needs **`task:write`** (+ client/project read). Until granted, `/tasks` returns 403 `insufficient_scope` and tickets stay in `Error` (saved locally).
- Utility-bar record capture is only reliable in console apps; the URL is always available.

## La pagina de registro (y por que no es un Layout)

- **El layout por defecto lo autogenera la org con un nombre que depende de su idioma**
  ("Formato Veleiro Ticket" en espanol). Un `Layout` empaquetado entra como un segundo layout
  **sin asignar**, asi que el cliente sigue viendo la pagina autogenerada con cuatro campos.
  La pagina de registro vive por eso en `flexipages/Veleiro_Ticket_Record` y se asigna desde el
  paquete con `actionOverrides` (`View`, formFactor `Large` y `Small`) en el `.object-meta.xml`.
  El layout se queda solo para el modal de New/Edit estandar.
- **Los campos los pinta `veleiroTicketDetail`, no secciones de campo del flexipage.** Las
  etiquetas de seccion de un flexipage son texto plano y no siguen el idioma del usuario;
  `lightning-record-form` toma la etiqueta de cada campo del metadata, que Salesforce ya traduce.
- **Contrato real de un flexipage** (sale de probar contra una org, no de la doc):
  `flexipage:fieldSection` referencia su facet con `body` como `valueList` de **un** nombre y la
  propiedad `columns` tambien se interpreta como nombre de facet, no como numero; `mode>Replace`
  solo se permite si la pagina tiene `parentFlexiPage`; `flexipage:tabset` no acepta `label`; y un
  LWC se referencia por su nombre pelado (`veleiroTicketPanel`), no como `c:veleiroTicketPanel`.
- **Un deploy es atomico.** Si el flexipage falla, los LWC del mismo deploy no quedan en la org
  aunque el reporte diga "79/80": despliega componentes primero y la pagina despues.
- **No hay pestana de Chatter a proposito.** Veleiro todavia no tiene endpoint de comentarios, y
  un feed en Salesforce seria una conversacion que Veleiro nunca ve.

## La vista avanzada (Veleiro Ticket Advance View)

- **Las list views de Salesforce no alcanzan dentro de un paquete.** El Kanban solo agrupa por
  picklists **editables**, su configuracion de columnas no es metadata empaquetable, y una list
  view que viaja en un paquete administrado le llega al cliente en **solo lectura**: no puede
  agregarle un filtro, solo clonarla. Por eso los tickets tienen su propia tab,
  `flexipages/Veleiro_Ticket_Board` + `lwc/veleiroTicketBoard`, con tablero y lista.
- **El filtrado pasa en el navegador.** `VeleiroTicketBoardController.load()` manda todos los
  tickets (tope `maxRows`, 2000) y el LWC filtra sobre eso: son los tickets de un solo cliente y
  filtrar sin ir al servidor es lo que hace que la vista se sienta viva. Si se llega al tope la
  vista lo dice; nunca muestra un numero incompleto como si fuera el total.
- **Arrastrar escribe en Veleiro ANTES que en Salesforce** (`VeleiroTicketMove.toStage`). El orden
  importa: la version anterior cambiaba `Work_Status__c` local y la siguiente bajada lo borraba en
  silencio, asi que la persona creia haber movido algo que nunca se movio. Si la API rechaza, en
  Salesforce no cambia nada y el LWC avisa ramificando por `code`
  (`not_allowed`, `no_such_stage`, `not_in_veleiro`, `version_conflict`).
- **`Client_Allowed_States__c` es el candado real, no el permiso del campo.** El campo del Kanban
  tuvo que volverse editable para que Salesforce lo ofreciera como agrupador, asi que la regla de
  a que etapas puede mover el cliente vive en `VeleiroTicketMove.allowed()`. Acepta el nombre del
  estado de Veleiro ("UAT") o el tipo ("review"), un valor por linea; en blanco no restringe.
- **`VeleiroTicketStates` resuelve tipo -> id de estado** con `/tasks/states`, una vez por
  transaccion. Cuando dos estados comparten tipo (un partner tenia "Input Required" y "Action
  Needed", ambos `blocked`) gana el primero por nombre: la eleccion tiene que ser **estable**, o
  el mismo arrastre caeria en un estado distinto cada vez.
- **Las etiquetas de las etapas salen de `c/veleiroTicketI18n`, no del describe del picklist.** Los
  labels de un picklist empaquetado no siguen el idioma del usuario sin Translation Workbench.

## Commands

```bash
scripts/deploy.sh <org>              # deploy, RunSpecifiedTests with every *Test class
scripts/deploy.sh <org> --validate   # dry run
sf apex run test -o <org> -n VeleiroTicketControllerTest,VeleiroTicketRoutingTest,VeleiroTicketServiceTest -c -w 10 -r human
sf apex run test -o <org> -t VeleiroTicketRoutingTest.<method> -w 10 -r human
```

**Never deploy with `RunLocalTests`**: it runs every test in the target org, and other packages' failing tests block the install. With `RunSpecifiedTests` each class needs ≥75% coverage on its own, so every new Apex class needs a test. When testing coexistence, deploy the kit and this package into the same scratch org and run both suites.

## Language

Code/API names in English; comments and some UI copy mix Spanish/English following the kit's convention. Follow the existing style per file.
