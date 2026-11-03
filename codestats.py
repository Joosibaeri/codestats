#!/usr/bin/env python3
"""CodeStats: token and cost usage across installed coding agents.

Sums tokens and cost over a time range across every coding agent whose local
data can be read, read-only:

  OpenCode   ~/.local/share/opencode/opencode.db   (session_v2 + session_message)
  Mammouth   ~/.local/share/mammouth/opencode.db   (OpenCode fork, message table)
  Codex      ~/.codex/state_5.sqlite               (threads.tokens_used)
  Claude     ~/.claude/projects/*/*.jsonl          (assistant message usage)

Time ranges (--range): month, last-month, year, last-year, all, 7d, 30d.
Each source yields the same stats dict; `render` merges them and prints one
JSON line with everything the popup panel needs.

Counting:
  Fresh usage = input + output + reasoning (+ totals Codex reports as one number).
  Cache re-reads are reported separately: agents re-report the whole context
  as cache.read on EVERY assistant step, so lumping it in would inflate
  "tokens used" ~25x.

Run with --debug for a human-readable audit.
"""
import argparse
import json
import sqlite3
import sys
from datetime import datetime, timedelta
from pathlib import Path

BRAND = "CodeStats"
HOME = Path.home()
RANGES = ["month", "last-month", "year", "last-year", "all", "30d", "7d"]


def fmt(n: int) -> str:
    n = int(n)
    if n >= 1_000_000:
        v = n / 1_000_000
        return f"{v:.1f}M" if v < 100 else f"{v:.0f}M"
    if n >= 1_000:
        v = n / 1_000
        return f"{v:.1f}K" if v < 100 else f"{v:.0f}K"
    return str(n)


def model_key(d: dict) -> str:
    m = d.get("modelID") or d.get("model")
    if isinstance(m, dict):
        m = m.get("modelID") or m.get("id") or "?"
    if m is None and d.get("id"):
        m = d.get("id")
    return str(m or "?")


def ms(dt: datetime) -> int:
    return int(dt.timestamp() * 1000)


def resolve_range(name: str, now: datetime) -> tuple:
    """Return (start_ms, end_ms, label) for a range name. End is exclusive."""
    first_this_month = datetime(now.year, now.month, 1)
    first_last_month = (first_this_month - timedelta(days=1)).replace(day=1)
    first_this_year = datetime(now.year, 1, 1)
    end_of_time = ms(datetime(9999, 1, 1))
    if name == "last-month":
        return ms(first_last_month), ms(first_this_month), first_last_month.strftime("%B %Y")
    if name == "year":
        return ms(first_this_year), end_of_time, now.strftime("%Y")
    if name == "last-year":
        return (ms(datetime(now.year - 1, 1, 1)), ms(first_this_year),
                str(now.year - 1))
    if name == "all":
        return 0, end_of_time, "All time"
    if name == "30d":
        return ms(now - timedelta(days=30)), end_of_time, "Last 30 days"
    if name == "7d":
        return ms(now - timedelta(days=7)), end_of_time, "Last 7 days"
    return ms(first_this_month), end_of_time, now.strftime("%B %Y")


def empty_stats() -> dict:
    return {
        "msgs": 0, "prompts": 0, "sessions": set(),
        "input": 0, "output": 0, "reasoning": 0, "other": 0,
        "cache_read": 0, "cache_write": 0, "cost": 0.0,
        "models": {},
    }


def model_bucket(stats: dict, name: str) -> dict:
    return stats["models"].setdefault(
        name, {"prompts": 0, "steps": 0, "input": 0, "output": 0, "reasoning": 0})


def ro(path: Path) -> sqlite3.Connection:
    return sqlite3.connect(f"file:{path}?mode=ro", uri=True, timeout=5)


def collect_mammouth(db: Path, start: int, end: int) -> dict:
    """Message-level aggregation of Mammouth's OpenCode-fork database."""
    con = ro(db)
    try:
        stats = empty_stats()
        for sid, row_tc, data in con.execute(
            "SELECT session_id, time_created, data FROM message"
        ):
            try:
                d = json.loads(data)
            except Exception:
                continue
            t = (d.get("time") or {}).get("created", row_tc)
            try:
                t = int(t)
            except Exception:
                continue
            if not start <= t < end:
                continue
            if d.get("role") == "user":
                # One user message = one prompt. Assistant messages fan out
                # ~10x via tool-call loops, so they must not be "Messages".
                stats["prompts"] += 1
                model_bucket(stats, model_key(d))["prompts"] += 1
                stats["sessions"].add(sid)
                continue
            if d.get("role") != "assistant" or not isinstance(d.get("tokens"), dict):
                continue
            tk = d["tokens"]
            cache = tk.get("cache") or {}
            try:
                i = int(tk.get("input") or 0)
                o = int(tk.get("output") or 0)
                r = int(tk.get("reasoning") or 0)
                cr = int(cache.get("read") or 0)
                cw = int(cache.get("write") or 0)
                c = float(d.get("cost") or 0)
            except Exception:
                continue
            stats["input"] += i
            stats["output"] += o
            stats["reasoning"] += r
            stats["cache_read"] += cr
            stats["cache_write"] += cw
            stats["cost"] += c
            stats["msgs"] += 1
            stats["sessions"].add(sid)
            b = model_bucket(stats, model_key(d))
            b["steps"] += 1
            b["input"] += i
            b["output"] += o
            b["reasoning"] += r
        stats["sessions"] = len(stats["sessions"])
        return stats
    finally:
        con.close()


def collect_opencode(db: Path, start: int, end: int) -> dict:
    """OpenCode's current database: per-session token totals in session_v2."""
    con = ro(db)
    try:
        stats = empty_stats()
        rows = con.execute(
            """SELECT id, model, tokens_input, tokens_output, tokens_reasoning,
                      tokens_cache_read, tokens_cache_write, cost
               FROM session_v2 WHERE time_created >= ? AND time_created < ?""",
            (start, end),
        ).fetchall()
        for sid, model, i, o, r, cr, cw, c in rows:
            try:
                name = model_key(json.loads(model)) if model else "?"
            except Exception:
                name = "?"
            prompts = con.execute(
                """SELECT COUNT(*) FROM session_message
                   WHERE session_id = ? AND type = 'user'
                     AND time_created >= ? AND time_created < ?""",
                (sid, start, end),
            ).fetchone()[0]
            i, o, r = int(i or 0), int(o or 0), int(r or 0)
            stats["input"] += i
            stats["output"] += o
            stats["reasoning"] += r
            stats["cache_read"] += int(cr or 0)
            stats["cache_write"] += int(cw or 0)
            stats["cost"] += float(c or 0)
            stats["prompts"] += prompts
            stats["sessions"].add(sid)
            b = model_bucket(stats, name)
            b["prompts"] += prompts
            b["steps"] += 1
            b["input"] += i
            b["output"] += o
            b["reasoning"] += r
            stats["msgs"] += 1
        stats["sessions"] = len(stats["sessions"])
        return stats
    finally:
        con.close()


def collect_codex(db: Path, start: int, end: int) -> dict:
    """Codex threads: only a total token count per thread is recorded."""
    con = ro(db)
    try:
        stats = empty_stats()
        for tid, created_ms, created_s, model, used in con.execute(
            "SELECT id, created_at_ms, created_at, model, tokens_used FROM threads"
        ):
            t = int(created_ms) if created_ms is not None else int(created_s or 0) * 1000
            if not start <= t < end:
                continue
            used = int(used or 0)
            stats["other"] += used
            stats["sessions"].add(tid)
            stats["msgs"] += 1
            b = model_bucket(stats, str(model or "?"))
            b["steps"] += 1
            b["input"] += used
        stats["sessions"] = len(stats["sessions"])
        return stats
    finally:
        con.close()


def collect_claude(root: Path, start: int, end: int) -> dict:
    """Claude Code transcripts. Streamed messages repeat, so dedupe by message id."""
    stats = empty_stats()
    seen = set()
    for f in root.glob("*/*.jsonl"):
        try:
            lines = f.read_text(errors="replace").splitlines()
        except OSError:
            continue
        for line in lines:
            try:
                obj = json.loads(line)
            except Exception:
                continue
            try:
                t = ms(datetime.fromisoformat(str(obj.get("timestamp")).replace("Z", "+00:00")))
            except Exception:
                continue
            if not start <= t < end:
                continue
            msg = obj.get("message") or {}
            sid = obj.get("sessionId")
            if obj.get("type") == "user" and isinstance(msg.get("content"), str):
                stats["prompts"] += 1
                model_bucket(stats, "?")["prompts"] += 1
                if sid:
                    stats["sessions"].add(sid)
                continue
            usage = msg.get("usage")
            if obj.get("type") != "assistant" or not isinstance(usage, dict):
                continue
            mid = msg.get("id")
            if mid:
                if mid in seen:
                    continue
                seen.add(mid)
            i = int(usage.get("input_tokens") or 0)
            o = int(usage.get("output_tokens") or 0)
            stats["input"] += i
            stats["output"] += o
            stats["cache_read"] += int(usage.get("cache_read_input_tokens") or 0)
            stats["cache_write"] += int(usage.get("cache_creation_input_tokens") or 0)
            stats["msgs"] += 1
            if sid:
                stats["sessions"].add(sid)
            b = model_bucket(stats, str(msg.get("model") or "?"))
            b["steps"] += 1
            b["input"] += i
            b["output"] += o
    stats["sessions"] = len(stats["sessions"])
    return stats


def sources() -> list:
    """(agent name, collector, path). Missing data is skipped."""
    return [
        ("OpenCode", collect_opencode, HOME / ".local/share/opencode/opencode.db"),
        ("Mammouth", collect_mammouth, HOME / ".local/share/mammouth/opencode.db"),
        ("Codex", collect_codex, HOME / ".codex/state_5.sqlite"),
        ("Claude Code", collect_claude, HOME / ".claude/projects"),
    ]


def fresh_of(s: dict) -> int:
    return s["input"] + s["output"] + s["reasoning"] + s["other"]


def render(results: list, label: str) -> dict:
    total = empty_stats()
    total["sessions"] = 0
    agents = []
    for name, s in results:
        agents.append({
            "name": name, "fresh": fresh_of(s), "cost": round(s["cost"], 4),
            "sessions": s["sessions"], "prompts": s["prompts"],
        })
        total["input"] += s["input"]
        total["output"] += s["output"]
        total["reasoning"] += s["reasoning"]
        total["other"] += s["other"]
        total["cache_read"] += s["cache_read"]
        total["cache_write"] += s["cache_write"]
        total["cost"] += s["cost"]
        total["msgs"] += s["msgs"]
        total["prompts"] += s["prompts"]
        total["sessions"] += s["sessions"]
        for k, v in s["models"].items():
            t = model_bucket(total, k)
            for f in ("prompts", "steps", "input", "output", "reasoning"):
                t[f] += v[f]

    fresh = fresh_of(total)
    cached = total["cache_read"] + total["cache_write"]
    models = [
        {"name": k, "prompts": v["prompts"], "steps": v["steps"],
         "fresh": v["input"] + v["output"] + v["reasoning"]}
        for k, v in sorted(total["models"].items(),
                           key=lambda kv: -(kv[1]["input"] + kv[1]["output"]
                                            + kv[1]["reasoning"]))
    ]
    return {
        "display": f"{fmt(fresh)} · ${total['cost']:.2f}",
        "label": label,
        "fresh": fresh,
        "input": total["input"], "output": total["output"],
        "reasoning": total["reasoning"],
        "cache": cached,
        "cost": round(total["cost"], 4),
        "sessions": total["sessions"],
        "prompts": total["prompts"], "steps": total["msgs"],
        "models": models,
        "agents": agents,
        "tooltip": (
            f"{BRAND} · {label}\n"
            f"{fmt(fresh)} fresh ({fresh:,}) · ${total['cost']:.2f} · "
            f"{total['sessions']} sessions · {total['prompts']} prompts"
        ),
    }


def collect_all(start: int, end: int) -> tuple:
    """Collect every present source. Returns (results, errors)."""
    results, errors = [], []
    for name, fn, path in sources():
        if not path.exists():
            continue
        try:
            results.append((name, fn(path, start, end)))
        except Exception as e:
            errors.append(f"{name}: {e}")
    return results, errors


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--range", choices=RANGES, default="month",
                    help="time range to sum (default: month)")
    ap.add_argument("--debug", action="store_true",
                    help="human-readable audit instead of JSON")
    args = ap.parse_args()
    now = datetime.now()
    start, end, label = resolve_range(args.range, now)

    if args.debug:
        print(f"range: {args.range} -> {label} (start={start}, end={end})")
        for name, fn, path in sources():
            print(f"{name:12} {path} (exists={path.exists()})")
        results, errors = collect_all(start, end)
        for name, s in results:
            print(f"\n[{name}] prompts={s['prompts']} sessions={s['sessions']} "
                  f"fresh={fresh_of(s):,} cost=${s['cost']:.4f} "
                  f"cache={s['cache_read'] + s['cache_write']:,}")
        for e in errors:
            print(f"error: {e}")
        return 0

    results, errors = collect_all(start, end)
    if not results:
        print(json.dumps({
            "display": "—", "label": label,
            "fresh": 0, "input": 0, "output": 0, "reasoning": 0,
            "cache": 0, "cost": 0, "sessions": 0,
            "prompts": 0, "steps": 0,
            "models": [], "agents": [],
            "tooltip": f"{BRAND} · {label}\nNo coding-agent data yet.",
        }))
        return 0
    data = render(results, label)
    data["range"] = args.range
    if errors:
        data["error"] = "; ".join(errors)
    print(json.dumps(data))
    return 0


if __name__ == "__main__":
    sys.exit(main())
