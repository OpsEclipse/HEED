# Composio Agent Tools

## Goal

Let the task-prep agent use Composio tools for Gmail, Google Calendar, and Google Drive when the user saves a Composio API key.

## Scope

- Add Composio API key storage in Keychain.
- Create a Composio Tool Router session [a scoped remote tool session] for each prep conversation.
- Append the Composio MCP tool [remote tool server access] to the existing OpenAI Responses tool list.
- Keep local transcript, context draft, and spawn tools unchanged.
- Update tests and docs.

## Non-Goals

- Do not add a new saved-data format.
- Do not persist prep chat, prep briefs, Composio session URLs, or remote tool outputs.
- Do not add broad all-toolkit Composio access.
- Do not build a full MCP approval UI in this slice.

## Risks

- Composio account connection may fail or require user auth outside this app.
- Remote tools can read sensitive external data.
- Write tools can send email or change calendar events.
- OpenAI MCP approvals are not handled by the app yet, so the tool is configured with `require_approval: never`.

## Decision Log

- Use Composio Tool Router REST from Swift because there is no Swift Composio SDK in this app.
- Restrict the session to `gmail`, `googlecalendar`, and `googledrive`.
- Disable Composio workbench tools because this app only needs connected app tools.
- Store the Composio API key in Keychain beside the OpenAI key.
- Generate and store a local Composio user ID in `UserDefaults` so connected accounts are scoped to this app install without exposing the macOS username.

## Progress Log

- Added `ComposioToolRouterSessionProvider`.
- Added Composio API key settings.
- Updated `OpenAITaskPrepConversationService` to append the Composio MCP tool when configured.
- Added tests for Composio session creation, request payloads, and OpenAI tool payloads.
- Updated README, architecture, frontend, reliability, and security docs.

## Open Questions

- Should the app add a visible per-tool approval UI before allowing write tools?
- Should users be able to choose connected account IDs when they have multiple Gmail or calendar accounts?
- Should Google Drive stay enabled, or should the first release be Gmail and Google Calendar only?

## Validation Steps

- Run targeted unit tests for API key settings, Composio session creation, and OpenAI request construction.
- Manually save a Composio API key.
- Start task prep and verify the first OpenAI request includes the Composio MCP tool.
- Try a Gmail read request, then an email send request that requires user confirmation in chat before the write.

## Observable Acceptance Criteria

- The API key sheet has a Composio API key field.
- Without a Composio API key, prep requests include only local tools.
- With a Composio session provider, prep requests include a fourth tool with `type: mcp`, `server_label: composio`, and the Composio MCP URL.
- The Composio session request enables only Gmail, Google Calendar, and Google Drive.
