# Veleiro Ticket Intake

A tiny Salesforce add-on that lets people **raise a ticket from anywhere in Salesforce**
and mirrors it as a **task in Veleiro**. Meant to be installed in a client's own
Salesforce org (e.g. a delivery engagement) so their users can file issues without
leaving Salesforce — the page URL and record context travel with the ticket.

This is a **separate product** from `veleiro-salesforce-kit` (which is the sales-motion
integration for a partner's own org). Each installs on its own, in any order, and they can
live in the same org without clashing: every component here has its own `VeleiroTicket*` /
`Veleiro_Ticket_*` name, including its own config, token and Named Credentials.

### Works better with the kit (optional)

If `veleiro-salesforce-kit` is installed and a ticket is raised from a record it already
linked, the ticket is filed under that record's Veleiro client/project instead of the
default from the setup panel:

| Raised from | Filed under |
|---|---|
| Opportunity with `Veleiro_Project_Id__c` | its project, and its Account's client |
| Account with `Veleiro_Client_Id__c` | that client (the configured project only if it's the same client) |
| Any record with an `AccountId` (Contact, Case, …) | its Account's client |
| Anything else, or no kit | the configured client/project |

The kit fields are read dynamically (`VeleiroTicketRouting`), so there is no dependency.

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

## If something fails

- A ticket that couldn't reach Veleiro stays in **Error** with the reason in `Sync_Error__c`. Fix the cause (usually the token or its `task:write` scope) and use the **Resend ticket to Veleiro** action on the record — no need to file it again.
- Files over 4 MB aren't attached; the ticket is still created and says so in `Attachment note`.

## Install

```bash
# Deploy (runs only this package's tests; add --validate for a dry run)
scripts/deploy.sh <org>
sf org assign permset -n Veleiro_Ticket_Intake_User -o <org>
# then connect from the Veleiro Ticket Setup tab (token + Production/Beta)
```

Deploying from the Veleiro platform instead? Pick **Run specified tests** with
`VeleiroTicketControllerTest, VeleiroTicketRoutingTest, VeleiroTicketServiceTest`.
Don't use Run local tests: it runs every test in the org, including code you don't own.

For a scratch org: `sf org create scratch -f config/project-scratch-def.json -a VeleiroTicketDev -d 30`.

Add the `Veleiro Ticket Intake` component to any Lightning app's **Utility Bar**
(App Manager → Edit → Utility Items) so it's reachable from anywhere.

## Config lives as data, not source

The API token is stored only in the `Veleiro_Ticket_Config__c` custom setting in the
org — never in git. Base URL / environment is controlled by the `Veleiro_Ticket_API`
(prod) or `Veleiro_Ticket_API_Beta` Named Credential.
