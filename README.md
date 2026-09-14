# Veleiro Ticket Intake

A tiny Salesforce add-on that lets people **raise a ticket from anywhere in Salesforce**
and mirrors it as a **task in Veleiro**. Meant to be installed in a client's own
Salesforce org (e.g. a delivery engagement) so their users can file issues without
leaving Salesforce — the page URL and record context travel with the ticket.

This is a **separate product** from `veleiro-salesforce-kit` (which is the sales-motion
integration for a partner's own org). It reuses the same proven Veleiro API plumbing.

## What it does

- A **utility-bar / record-page LWC** (`veleiroTicketIntake`) with a small form:
  Title, Description, Type, Priority, Due date, and file attachments (paste a screenshot
  or browse). It auto-captures the **page URL** and the **record/object** the user was on.
- On submit it creates a `Veleiro_Ticket__c` record (attachments stored as Salesforce
  Files) and, asynchronously, **creates the matching task in Veleiro** via the API.
- A **setup panel** (`veleiroTicketConfig`) to connect (API token) and **map** which
  Veleiro **client** and **project** this org's tickets are filed under — with dropdowns
  populated from live Veleiro data.

## What the Veleiro API allows (and doesn't)

- ✅ Create task (`POST /tasks`): title (required), description, ticket_type, priority,
  client_id, project_id, additional_fields (free JSON — carries `sf_record_url`,
  `sf_object`, `sf_record_id`, etc.). Due date is a follow-up `PATCH`.
- ❌ **No file/attachment endpoint.** Screenshots stay in Salesforce (Files) for now; only
  their context (the URL) is sent. When Veleiro adds attachment upload, wire it here.
- ❌ No `parent` / `assignee` (“Who executes”) fields in the public API — omitted.
- ⚠️ The API token needs **`task:write`** plus **client/project read**. Grant it in the
  Veleiro portal before the push works (`GET /api/v1/me` must show `task.level = write`).

## Install (scratch/dev)

```bash
sf org create scratch -f config/project-scratch-def.json -a VeleiroTicketDev -d 30
sf project deploy start -o VeleiroTicketDev
sf org assign permset -n Veleiro_Ticket_Intake_User -o VeleiroTicketDev
# then paste your token: Setup > Custom Settings > Veleiro Config > Manage (Api_Token__c)
sf org open -o VeleiroTicketDev
```

Add the `Veleiro Ticket Intake` component to any Lightning app's **Utility Bar**
(App Manager → Edit → Utility Items) so it's reachable from anywhere.

## Config lives as data, not source

The API token is stored only in the `Veleiro_Config__c` protected custom setting in the
org — never in git. Base URL / environment is controlled by the `Veleiro_API`
(prod) or `Veleiro_API_Beta` Named Credential.
