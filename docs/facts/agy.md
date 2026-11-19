# Antigravity CLI (`agy`) facts

What Nushi depends on, as seen when it was built against the version named below. Read it before changing the code that talks to it.

## Agent facts (agy 1.5.12)

What the code depends on (`internal/agy*`), from driving `agy acp` 1.5.12 on Windows on 2026-11-19 in throwaway workspaces, and from `agy`'s built-in customization docs.

**Start and version (seen)**
- `agy acp` speaks ACP as JSON lines on stdio. Closing its stdin makes it exit cleanly with status 0 (`StopBySignal` isn't needed).
- `agy --version` prints `1.5.12` and exits 0.
- Resume in a terminal: `agy --conversation <session id>`.

**initialize (seen)**
- `protocolVersion` 1, `agentInfo` `Antigravity ACP Server` `1.5.12`, `loadSession: true`, `promptCapabilities` `image: true`, `audio: false`, `embeddedContext: true`, `sessionCapabilities` `additionalDirectories`, `close`, `list`, `load` and `resume` (no `fork` or `delete`: `session/fork` and `session/delete` both answer `-32601 Method not found`), `auth.logout`, and auth methods `oauth-personal`, `oauth-business`, `gemini-api-key`, `agent-platform`.

**Sessions (seen)**
- `session/new` (`cwd`, `mcpServers`) answers a UUID `sessionId`, legacy `models` and `modes`, and `configOptions`:
  - `model` (category `model`): e.g. `gemini-4-neon`, `gemini-4-argon`, `gemini-4-hydrogen`, `gemini-3.8-flash`, `claude-opus-5-5`, `claude-sonnet-5-5`, `gpt-oss-120b-medium`.
  - `thought_level` (category `thought_level`): the model's levels (`low`, `medium`, `high`, and `xhigh` on models that have it).
  - `mode` (category `mode`): `default`, `accept-edits`, `auto`, `plan`.
- After `session/new` it sends `available_commands_update` (slash commands and discovered skills) and `usage_update` (`used: 0, size: 1048576`).
- `session/set_config_option` answers with the full updated `configOptions` (switching models updates `thought_level` options) and also sends `config_option_update` and `available_commands_update`. Selections persist across `session/load` and `session/resume`.
- `plan` mode is **not** read-only: when asked to edit a file in `plan` mode, `agy` wrote its plan artifact and still called `edit_file` on the workspace file. So Nushi counts no mode of `agy` as `ReadOnly`.
- `session/list` lists prompted sessions (`sessionId`, `cwd`, `title`, `updatedAt`). On Windows, `cwd` arrives in file-URI path form with a leading slash (`"/C:/Users/..."`), which `chats.Find` normalizes to a native Windows path so folder filtering and `os.Stat` match.
- `session/load` replays `user_message_chunk`, `tool_call` (`completed`) and `agent_message_chunk`, answers with `configOptions`, and then sends `usage_update`, `available_commands_update` and `session_info_update`. `session/resume` replays nothing. `session/close` answers `{}`.
- `agy` titles sessions itself soon after the first prompt (`session_info_update` with `title`), so `NamesSessions` is on.

**Turns, permissions and questions (seen)**
- A turn streams `tool_call` / `tool_call_update`, `agent_message_chunk` and `usage_update`, and ends with `{stopReason: "end_turn", usage: {...}}`. Edits carry ACP `diff` content.
- `session/request_permission` sends `options`: `allow` (`allow_once`) and `deny` (`reject_once`).
- Questions (`ask_question`): over `elicitation/create` (`mode: "form"`), each choice question `qN` (`oneOf`) is followed by a free-text field `qN_other` titled `"Other"` (`Harness.Other`).

**A client's MCP servers (seen; `ClientMCP: true`)**
- `agy acp` starts stdio MCP servers passed in `session/new`'s `mcpServers` and exposes their tools directly as `mcp_<server>_<tool>` (e.g. `mcp_nushi_show`), titled `"Run mcp_<server>_<tool>"` on both `tool_call` and `session/request_permission`.
- In `default` mode, calling `mcp_nushi_show` asks permission via `session/request_permission` with `rawInput` carrying the arguments (`{"path": ...}`), meeting ADR 0068's requirement. `Harness.ToolCall` strips the leading `"Run "` from `"Run mcp_..."`, and Nushi's `isShow` / `isPreviewStart` and the app's `tool_parts.dart` recognize `mcp_nushi_` (with or without `"Run "`).

**What a folder brings (seen; `internal/agytrust`)**
- No folder trust prompt and no trust record. Starting a session in a folder with `.agents/hooks.json` (`SessionStart` hook) ran the hook command without asking.
- Customization discovery walks from the chat's folder up to the repository's root (skipping `$HOME`), checking `.agents/`, `.agent/`, `_agents/` and `_agent/` for `hooks.json`, `mcp_config.json`, `plugins/`, `plugins.json` and `skills.json` (which can register or inherit external paths). Instructions (`GEMINI.md`, `AGENTS.md`, `rules/`, `skills/`) are left out of the trust card, as on Claude's and omp's cards (ADR 0031).

**Skills (seen and from customization docs; `internal/agyskills`)**
- Discovered from `.agents/skills` (`shared`), `.agent/skills`, `_agents/skills` and `_agent/skills` (`project`) walking from the chat's folder up to the repository's root (skipping `$HOME`), plus global `~/.gemini/config/skills` (`user`). First match by name wins.
- Format: `<root>/<name>/SKILL.md` with YAML front matter `name` and `description`.
- `agy` has no per-skill on/off switch for discovered skills (`NoSwitch`); deleting a skill moves its folder to the Trash.
