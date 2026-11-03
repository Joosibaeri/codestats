# CodeStats

An Omarchy bar widget that shows token and cost usage across installed coding
agents, for a chosen time range.

Clicking the bar icon opens a popup with:

- a time-range selector: 7d, 30d, Month, Last month, Year, Last year, All
- totals: fresh tokens, cost, sessions, prompts
- a per-agent split (OpenCode, Mammouth, Codex, Claude Code)
- a per-model split

Middle click opens the Mammouth terminal stats.

## Data sources (read-only)

| Agent       | Location                                  |
|-------------|-------------------------------------------|
| OpenCode    | `~/.local/share/opencode/opencode.db`     |
| Mammouth    | `~/.local/share/mammouth/opencode.db`     |
| Codex       | `~/.codex/state_5.sqlite`                 |
| Claude Code | `~/.claude/projects/*/*.jsonl`            |

Agents without data on the machine are skipped.

Fresh tokens = input + output + reasoning. Cache re-reads are reported
separately, because agents re-send the whole context on every step.

## Install

Copy the folder to `~/.config/omarchy/plugins/joosibaeri.codestats/` and add
`{ "id": "joosibaeri.codestats" }` to the bar's section in
`~/.config/omarchy/shell.json`.

Check the helper from the command line:

```sh
python3 codestats.py --range last-month
python3 codestats.py --debug
```
