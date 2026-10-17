#!/usr/bin/env python3
"""scrub-transcripts.py: replace known secret VALUES in agent transcripts, logs and notes
with a pointer to the file that holds them:  [SECRET -> /root/.mailer-api-key]

How it knows what a secret is:
  * every regular file matching SECRET_GLOBS that is mode 600 (owner-only) is read;
    each non-empty line (or KEY=VALUE value) of 12+ chars becomes an inventory entry
  * plus any extra files you pass with --extra (e.g. an app's .env)

Usage:
  scrub-transcripts.py --dry-run DIR [DIR...]        count, change nothing
  scrub-transcripts.py DIR [DIR...]                  scrub in place (atomic rewrite, same mode)
  scrub-transcripts.py --recent 60 DIR               only files modified in the last 60 min
  scrub-transcripts.py --find-unknown DIR            list key-SHAPED strings not in any locked file
  scrub-transcripts.py --extra /opt/app/.env DIR

Back up the directories (encrypted, 600) before the first real run.
"""
import argparse, glob, os, re, stat, sys, tempfile, time

SECRET_GLOBS = ["/root/.*", "/root/.secrets/*", "/home/agents/.secrets/*"]
MIN_LEN = 12
TEXT_EXT = {".jsonl", ".json", ".md", ".txt", ".log", ".out", ".err", ""}
# key-shaped strings, for --find-unknown (extend with your providers' prefixes)
KEY_SHAPES = re.compile(
    r"\b(sk_live_[A-Za-z0-9]{16,}|sk_test_[A-Za-z0-9]{16,}|rk_live_[A-Za-z0-9]{16,}"
    r"|sk-[A-Za-z0-9_-]{32,}|AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{40,}"
    r"|xox[abpr]-[A-Za-z0-9-]{20,}|AIza[0-9A-Za-z_-]{35}|glpat-[A-Za-z0-9_-]{20})\b")
# values that look secret-ish but aren't (add your own false positives)
IGNORE = {"changeme", "password123", "xxxxxxxxxxxxxxxx"}


def owner_only(path):
    try:
        st = os.stat(path)
    except OSError:
        return False
    return stat.S_ISREG(st.st_mode) and not (st.st_mode & 0o077) and st.st_size < 64 * 1024


def values_from(path):
    try:
        text = open(path, encoding="utf-8", errors="ignore").read()
    except OSError:
        return []
    out = []
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#") or line.startswith("-----"):
            continue
        m = re.match(r"^(?:export\s+)?[A-Za-z_][A-Za-z0-9_]*\s*[=:]\s*['\"]?(.+?)['\"]?$", line)
        v = m.group(1) if m else line
        if len(v) >= MIN_LEN and " " not in v and v.lower() not in IGNORE:
            out.append(v)
    return out


def build_inventory(extra):
    inv = {}
    paths = [p for g in SECRET_GLOBS for p in glob.glob(g) if owner_only(p)] + list(extra)
    for p in paths:
        for v in values_from(p):
            inv.setdefault(v, p)
    # longest first, so a value that contains another is replaced whole
    return dict(sorted(inv.items(), key=lambda kv: -len(kv[0])))


def iter_files(dirs, recent_min):
    cutoff = time.time() - recent_min * 60 if recent_min else 0
    for d in dirs:
        for root, _, files in os.walk(d):
            for f in files:
                p = os.path.join(root, f)
                if os.path.splitext(f)[1] not in TEXT_EXT:
                    continue
                try:
                    if os.path.getmtime(p) < cutoff or os.path.getsize(p) > 512 * 1024 * 1024:
                        continue
                except OSError:
                    continue
                yield p


def scrub_file(path, inv, dry):
    try:
        data = open(path, encoding="utf-8", errors="surrogateescape").read()
    except OSError:
        return 0
    hits = 0
    for val, src in inv.items():
        if val in data:
            n = data.count(val)
            hits += n
            data = data.replace(val, f"[SECRET -> {src}]")
    if hits and not dry:
        mode = stat.S_IMODE(os.stat(path).st_mode)
        fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".scrub-")
        with os.fdopen(fd, "w", encoding="utf-8", errors="surrogateescape") as fh:
            fh.write(data)
        os.chmod(tmp, mode)
        os.replace(tmp, path)
    return hits


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dirs", nargs="+")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--recent", type=int, default=0, metavar="MIN")
    ap.add_argument("--extra", action="append", default=[])
    ap.add_argument("--find-unknown", action="store_true")
    a = ap.parse_args()

    inv = build_inventory(a.extra)
    if a.find_unknown:
        known = set(inv)
        seen = set()
        for p in iter_files(a.dirs, a.recent):
            try:
                for m in KEY_SHAPES.finditer(open(p, encoding="utf-8", errors="ignore").read()):
                    k = m.group(0)
                    if k not in known and k not in seen:
                        seen.add(k)
                        # never print the value itself: prefix + length + where
                        print(f"unknown key-shaped string {k[:6]}…({len(k)} chars) in {p}")
            except OSError:
                pass
        print(f"{len(seen)} unknown. Save each to its own 600 file, then re-run the scrubber.")
        return

    total = files = 0
    for p in iter_files(a.dirs, a.recent):
        h = scrub_file(p, inv, a.dry_run)
        if h:
            total += h
            files += 1
    verb = "would scrub" if a.dry_run else "scrubbed"
    print(f"inventory {len(inv)} secret value(s); {verb} {total} copy/copies in {files} file(s)")


if __name__ == "__main__":
    sys.exit(main())
