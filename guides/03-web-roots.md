# 03 · Web roots

> **Goal:** nothing but the website is downloadable from the website.

## How backups end up public

The agent (or you) is about to edit `config.php`. The careful move is to back it up first:

```bash
cp config.php config.php.bak-20261012
```

That is careful. It is also a new public URL, `https://example.com/config.php.bak-20261012`, and because it doesn't end in `.php`, the server sends it as **plain text**. Database password, API keys and all.

Agents are *especially* good at this, because they're taught to back up before every edit. One busy month left us with:

- **31** `*.bak*` files downloadable from one personal site, on the agent box itself.
- **~180** backup and database files across the public folders of a shared hosting box. These included a site's **live 67 MB database dump** and config backups with passwords and keys for four different apps.

The access logs showed nobody outside had downloaded them, only our own checks. We got lucky. One config backup predated the logs, so we treated the keys in it as exposed and listed them for rotation.

## Rule 1: back up *outside* the docroot

```bash
# not this
cp /var/www/site/config.php /var/www/site/config.php.bak
# this
install -d -m 700 /root/site-baks-$(date +%F)
cp -p /var/www/site/config.php /root/site-baks-$(date +%F)/
```

Put it in your agent's instructions in those words: *"Backups go in /root/<site>-baks-<date>/, never next to the file."*

## Rule 2: the server refuses those files anyway

People forget rule 1. Rule 2 is the seatbelt. Block these by **extension/pattern** so a forgotten file 404s instead of downloading:

`*.bak*` `*.orig` `*.old` `*.save` `*.swp` `*~` `*.sql` `*.sql.gz` `*.dump` `*.tar*` `*.tgz` `*.zip` (if your site doesn't serve zips) `.env*` `.git/` `*.log` `wp-config.php.*` `composer.json/lock` `*.ini` `*.conf`

| Server | Rule |
|---|---|
| Caddy | [`scripts/webroot/caddy-block-snippet`](../scripts/webroot/caddy-block-snippet): define once, `import blockjunk` in **every** site block (including new ones) |
| Apache | [`scripts/webroot/apache-block.conf`](../scripts/webroot/apache-block.conf): global `conf-enabled`, or per vhost |
| nginx | [`scripts/webroot/nginx-block.conf`](../scripts/webroot/nginx-block.conf): `include` in each `server {}` |

**Test it** (expect 403/404, never 200):

```bash
for p in index.php.bak-test .env db.sql backup.tar.gz .git/config; do
  printf '%-22s ' "$p"; curl -s -o /dev/null -w '%{http_code}\n' "https://example.com/$p"
done
```

Add one of these probes to your daily sweep so you find out when a new site block forgot the `import`.

## Rule 3: sweep and move, never delete blind

[`scripts/webroot/move-baks-out.sh`](../scripts/webroot/move-baks-out.sh) finds the junk across all web roots, shows you the list (dry run by default), and with `--apply` *moves* the files to a dated folder under `/root`, keeping the paths and permissions. Nothing is deleted. You can always put one back.

## Rule 4: if it was public, assume it was read

If a config backup with keys was ever downloadable, **rotate those keys**. Moving the file only stops the *next* download. See [04 · Secrets](04-secrets.md).

Check your access logs for real downloads before you decide how urgent it is:

```bash
zgrep -hE '\.(bak[^ ]*|sql(\.gz)?|tar(\.gz)?|env)[ ?]' /var/log/apache2/*access*.log* \
  | awk '$9==200' | awk '{print $1, $7}' | sort | uniq -c | sort -rn | head
```

## Also check: world-readable files in `/tmp`

> **Seen in the wild:** seven old helper scripts in `/tmp`, still holding passwords, including root credentials for another server. Any site account on the box could read them.

`/tmp` is shared by every user on the box. Agents love writing scratch scripts there. Use `mktemp` with `umask 077`, or a private scratch dir like `/root/scratch` with mode `700`. Sweep for leftovers daily ([05](05-active-defense.md)).

## Checklist → [08-checklists.md#03](08-checklists.md#03--web-roots)
