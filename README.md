# CodeStats

An Omarchy bar widget that shows token and cost usage across installed coding
agents, for a chosen time range.

Clicking the bar icon opens a popup with:

- a time-range selector: 7d, Month, Year, All
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

## Remove

1. Delete the bar entry `{ "id": "joosibaeri.codestats" }` from
   `~/.config/omarchy/shell.json`.
2. Delete the plugin folder:

   ```sh
   rm -rf ~/.config/omarchy/plugins/joosibaeri.codestats
   ```

3. Restart the shell:

   ```sh
   omarchy-restart-shell
   ```

Nothing else is written to disk. The helper only reads the agents' data
files, so no cleanup is needed there.

Check the helper from the command line:

```sh
python3 codestats.py --range last-month
python3 codestats.py --debug
```
