# CLAUDE.md

Guidance for Claude Code working in this repo.

## What this is

`veleiro-ticket-intake` — a small Salesforce DX add-on (no namespace, sourceApiVersion
62.0) that lets end-users **raise a ticket from anywhere in Salesforce** and mirrors it
as a **task in Veleiro**. It installs into a **client's** org (delivery use case), and is
a **separate product** from `veleiro-salesforce-kit` (partner sales-motion). It reuses the
kit's proven API plumbing (`VeleiroApiClient`, Named Credentials, JSON-string LWC→Apex
transport, version/If-Match concurrency).

## Architecture

- `Veleiro_Ticket__c` — the local ticket; mirrors the Veleiro task fields the API supports
  and holds the match (`Veleiro_Task_Id__c` external id, key, version, status).
- `Veleiro_Config__c` (Hierarchy custom setting, Protected) — token + base URL + which
  Veleiro `client_id`/`project_id` this org files tickets under. Token is DATA, never git.
- `VeleiroApiClient` — server-to-server HTTP client. Contract: no trailing slash,
  `{data,has_more,next_cursor}` envelope, error branches by `error.code` (never message),
  409 `version_conflict` carries `detail.current_version`.
- `VeleiroTicketService` — `listClients`/`listProjects` (for the mapping dropdowns) and
  `pushTicket` (create task + optional due_date PATCH; records Sent/Error on the record,
  never throws).
- `VeleiroTicketController` — `@AuraEnabled` surface. `createTicket` takes a **JSON string**
  and `JSON.deserialize`s it (avoids the LWC→Apex `List<CustomClass>` null-marshaling bug).
  Insert-then-`enqueueJob` so the callout runs outside the DML transaction.
- `veleiroTicketIntake` LWC — utility-bar + record-page. Captures URL via
  `window.location.href` (reliable in any app type) and record/object via
  `CurrentPageReference` or URL parse. Files read client-side to base64, sent in payload.
- `veleiroTicketConfig` LWC — connect + map client/project.

## Hard facts (don't relearn these)

- The Veleiro API has **no file upload** endpoint (10 paths total). Screenshots stay in
  Salesforce Files; only context URLs go to Veleiro via `additional_fields`.
- Task create needs only `title`. `due_date`/`start_date`/`status` are PATCH-only.
- The token needs **`task:write`** (+ client/project read). Until granted, `/tasks` calls
  return 403 `insufficient_scope` and tickets stay in status `Error` (saved locally).
- Utility-bar auto-capture of the *record* is only reliable in console apps; the **URL** is
  always available via `window.location`, so that's the primary context source.

## Commands

```bash
sf project deploy start -o <org>
sf project deploy validate --source-dir force-app -o <org>
sf apex run test -o <org> -l RunLocalTests -w 10
```

## Language

Code/API names in English; comments and some UI copy mix Spanish/English following the
kit's convention. Follow the existing style per file.
