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

## Hard facts (don't relearn these)

- The Veleiro API has **no file upload** endpoint. Screenshots stay in Salesforce Files; only context goes to Veleiro via `additional_fields`.
- Task create needs only `title`. `due_date`/`start_date`/`status` are PATCH-only.
- `ticket_type` must be one of epic, story, task, decision, approval, review, deliverable, action_item, milestone, subtask; `priority` one of low, medium, high, critical (`urgent` → critical). `VeleiroTicketService` normalizes.
- The token needs **`task:write`** (+ client/project read). Until granted, `/tasks` returns 403 `insufficient_scope` and tickets stay in `Error` (saved locally).
- Utility-bar record capture is only reliable in console apps; the URL is always available.

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
