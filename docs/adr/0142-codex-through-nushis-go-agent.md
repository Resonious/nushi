# 0142. Codex through Nushi's Go agent (draft)

A draft: the Go agent is in and off by default; the default flips by an amendment once the conditions below hold.

## Context
Codex runs through codex-acp 2.2.2 under the user's Node ([0037](0037-agents-you-set-up.md)): a Set up that downloads 2.3 MB into 18.6 MB, Node on `PATH`, and a Node process per chat beside Codex. codex-acp is a translator: it starts `codex app-server`, Codex's own JSON-RPC protocol (one JSON object a line, no `"jsonrpc"` member), and speaks ACP to the client. Codex prints that protocol's schema itself (`codex app-server generate-json-schema`, `generate-ts`). npm's `codex` is a Node launcher too, in front of the native binary.

## Decision
- **Codex's native binary**, never npm's launcher, for the Go agent: it gets the binary the launcher would run as `CODEX_PATH`, with the variables the launcher sets that tell Codex how it was installed (`codex.Native`). codex-acp keeps the user's `codex` as it is, launcher included, while the Go agent is off by default.
- **An ACP agent in Go, a library**: `github.com/afrase/codex-acp-go`, the owner's module, as Claude's agent is claude-acp-go ([0066](0066-claude-through-nushis-go-agent.md)): `codexacp` (the agent), `appserver` (a client for the app-server: framing, calls, the server's notifications and requests, typed messages written from the schema) and `appserver/appservertest` (a scripted fake app-server). It keeps codex-acp's wire shape where Nushi reads it: Codex's thread ids as session ids, item ids as message ids, `terminal_output_delta` and `terminal_exit`, the permission options, `<id>_note`. It imports only the standard library and acp-go, and serves any ACP client (its `cmd/codex-acp`). Nushi keeps no copy: a fix lands in the library, then a new version here; its tests on a real Codex are the library's.
- **`nushid codex-acp`** runs it, one app-server per agent, started by the library's `appserver.Exec`: on Unix in the agent's process group, so the daemon's kill of the agent's group takes it too, as codex-acp's child app-server goes, and it stops by itself once its stdin closes; on Windows through a Spawn of Nushi's that guards an npm shim against cmd.exe (`batchfile`) before `appserver.Exec`. It reads codex's path from `CODEX_PATH`, as codex-acp does. Codex signs in by itself; the agent has no authentication code, and answers Authentication required when Codex has no login it needs.
- **Off by default.** `NUSHI_CODEX_ADAPTER=go` in the daemon's environment picks it, read when the daemon starts: Codex then has no adapter, no Node requirement and nothing to set up. There is no setting in the app yet: a visible switch waits until the agent loads, forks and lists sessions, so a chat can't land on an agent that can't reopen it.
- **The default flips** when the Go agent covers what Nushi uses of codex-acp (load and replay, fork and fork at a message, list, delete, steering, MCP approvals, plan-mode questions), recorded runs of codex-acp against a fake model replay through it with the same items, and the owner has used it for some days. Then the Node adapter, its Set up and `make adapters` go, by an amendment.
- **Licences.** The agent follows codex-acp's behaviour (Apache-2.0, JetBrains s.r.o.) and is written anew; the messages follow the schema Codex prints (Apache-2.0, OpenAI). The library's `NOTICE` says both; the schema itself isn't committed.

## Consequences
- Both agents use Codex's own thread ids and rollouts, so a chat moves between them while asleep.
- The Go agent depends on the app-server's experimental API (`experimentalApi`, as codex-acp asks): collaboration mode and some notifications are experimental and may change with Codex.
- Until runs are recorded, the Go agent's behaviour is codex-acp's as read in its source; what only a real run can confirm is listed in `docs/facts/codex.md`.

## Alternatives considered
- Staying on codex-acp: Node, a Set up, a Node process a chat.
- Running codex-acp's bundle on another JavaScript runtime: still a runtime, and nothing we can change.
- `codex exec` per prompt: no live permissions, steering, cancel or history.
