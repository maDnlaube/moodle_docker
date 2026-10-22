# Moodle 5.3 LTS in Docker — Caddy + Apache + MariaDB

A complete, production-ready [Moodle](https://moodle.org) learning platform
that you configure by editing **one text file** and start with **one
command**. HTTPS certificates are issued and renewed automatically — no
certbot, no cron jobs, no certificate files to copy around.

Built for aspiring Moodle administrators: if you can rent a server and edit
a text file, you can run your own Moodle.

```
your .env file  ──►  docker compose up -d --build  ──►  https://your-domain
```

Moodle 5.3 is a **long-term support (LTS)** release, so it receives security
fixes for years — a good base for a site you want to run without chasing
every new version.

> **Already running the Moodle 4.5 version of this repository?** Follow
> [Upgrading from Moodle 4.5](#upgrading-from-moodle-45) — a plain
> `git pull` is not enough.

---

## Contents

- [What you get](#what-you-get)
- [What you need](#what-you-need)
- [1. Quick start (the short version)](#1-quick-start-the-short-version)
- [2. Optional: try it on your own computer first](#2-optional-try-it-on-your-own-computer-first)
- [3. Deploy on a real server, step by step](#3-deploy-on-a-real-server-step-by-step)
- [4. Everyday operations](#4-everyday-operations)
- [5. Updating Moodle](#5-updating-moodle)
  - [Upgrading from Moodle 4.5](#upgrading-from-moodle-45)
- [6. Adding plugins](#6-adding-plugins)
- [7. Troubleshooting](#7-troubleshooting)
- [8. How it works](#8-how-it-works)
- [License](#license)

---

## What you get

Four cooperating containers, defined in [`docker-compose.yml`](docker-compose.yml):

```
                Internet (ports 80 + 443)
                          │
            ┌─────────────▼─────────────┐
            │ caddy — reverse proxy     │  gets + renews HTTPS
            │ with automatic HTTPS      │  certificates by itself
            └─────────────┬─────────────┘
                          │
            ┌─────────────▼─────────────┐     ┌────────────────────┐
            │ moodle — Apache + PHP     │     │ cron — background  │
            │ with Moodle 5.3 LTS       │     │ task runner        │
            └─────────────┬─────────────┘     └─────────┬──────────┘
                          │                             │
            ┌─────────────▼─────────────────────────────▼──────────┐
            │ db — MariaDB 11.4 LTS database                       │
            └──────────────────────────────────────────────────────┘
```

- **Caddy** answers all traffic from the internet and handles HTTPS
  completely automatically (via Let's Encrypt). Nothing else is reachable
  from outside.
- **Moodle** runs on Apache + PHP 8.3 using the official
  [`moodlehq/moodle-php-apache`](https://hub.docker.com/r/moodlehq/moodle-php-apache)
  base image, with the Moodle 5.3 LTS source code baked in at build time.
  Apache only serves Moodle's `public/` folder, so files such as
  `config.php` (which holds your database password) can never be
  downloaded. PHP comes tuned for Moodle out of the box (opcache sized for
  Moodle's code base, JIT compiler on, generous memory and upload limits).
- **Cron** runs Moodle's required background tasks every minute (email
  sending, notifications, cleanup). Many beginner setups forget this — here
  it's just part of the stack.
- **MariaDB** stores all data on a persistent Docker volume, as does the
  `moodledata` folder (uploaded files). You can rebuild or update the
  containers without losing anything.

**First-run automation:** on the very first start, the stack waits for the
database, installs Moodle, and creates your admin account from the values
in `.env` — there is no web installer to click through.

## What you need

For a real, public site:

1. **A Linux server** — either rented in the cloud (from ~5 €/month) or a
   physical machine you own. 2 GB RAM minimum, 4 GB comfortable.
2. **A domain name** (e.g. `moodle.yourschool.org`) pointing at that server.
3. **Docker** installed on the server.

No experience with Apache, PHP, databases or certificates is required.
If you're missing 1–3, the guide [docs/server-setup.md](docs/server-setup.md)
walks you through all of them — for cloud **and** physical servers.

For a test run on your own computer you only need
[Docker Desktop](https://www.docker.com/products/docker-desktop/) (macOS /
Windows) or Docker Engine (Linux).

---

## 1. Quick start (the short version)

For experienced users; everyone else should follow
[section 3](#3-deploy-on-a-real-server-step-by-step).

```sh
git clone https://github.com/maDnlaube/moodle_docker.git
cd moodle_docker
cp .env.example .env
nano .env                        # set domain, email, passwords
docker compose up -d --build     # build, install, start — first run takes a few minutes
docker compose logs -f moodle    # watch until "[moodle-stack] Moodle installed."
```

Then open `https://your-domain` and log in with the admin credentials from
your `.env`.

---

## 2. Optional: try it on your own computer first

You can run the whole platform locally before renting anything. With Docker
Desktop running:

```sh
git clone https://github.com/maDnlaube/moodle_docker.git
cd moodle_docker
cp .env.example .env
```

Open `.env` in any text editor and set:

```ini
MOODLE_DOMAIN=localhost
ACME_EMAIL=you@example.org            # any address; not used for localhost
MOODLE_ADMIN_PASSWORD=Test-Pass123!   # remember Moodle's password rules
MOODLE_ADMIN_EMAIL=you@example.org
DB_PASSWORD=local-test-password-1
DB_ROOT_PASSWORD=local-test-password-2
```

Then:

```sh
docker compose up -d --build
docker compose logs -f moodle    # wait for "[moodle-stack] Moodle installed."
```

Open **https://localhost** in your browser. You will see a certificate
warning — that is expected: for `localhost`, Caddy creates a self-signed
certificate because a public one is impossible. Click "Advanced" →
"Proceed" and log in.

On a localhost test site, two of Moodle's self-checks report problems that
a real server won't have: **Router** (under *Reports → System status*) and
**Public paths** (under *Reports → Security checks*). Moodle runs these by
fetching pages from its own address, and inside the container
`https://localhost` is not the website. Ignore them locally.

To throw the test site away completely:

```sh
docker compose down -v    # -v also deletes the data volumes
```

---

## 3. Deploy on a real server, step by step

### Step 1 — Prepare server, domain and Docker

Follow [docs/server-setup.md](docs/server-setup.md). When you're done you
have: a server you can SSH into, `docker compose version` working on it,
ports 80/443 open, and your domain resolving to the server's IP.

**Do not skip the domain check** — automatic HTTPS only works once
`ping your-domain` answers from your server's IP.

### Step 2 — Get this code onto the server

```sh
ssh yourname@your-server
git clone https://github.com/maDnlaube/moodle_docker.git
cd moodle_docker
```

### Step 3 — Create your configuration

```sh
cp .env.example .env
nano .env
```

`.env` is the **only file you need to edit**. Every setting is explained by
a comment above it. The required ones:

| Setting | What to put there |
|---|---|
| `MOODLE_DOMAIN` | Your domain, e.g. `moodle.yourschool.org` (no `https://`) |
| `ACME_EMAIL` | Your email — receives certificate expiry warnings (rare) |
| `MOODLE_ADMIN_USER` | Login name for the admin account (default `admin`) |
| `MOODLE_ADMIN_PASSWORD` | Admin password — min. 8 chars with upper/lower case, a digit and a symbol |
| `MOODLE_ADMIN_EMAIL` | Email of the admin account |
| `DB_PASSWORD` | Database password — generate with `openssl rand -base64 24` |
| `DB_ROOT_PASSWORD` | Second database password — generate another one |

Worth setting now (optional ones can wait):

| Setting | What to put there |
|---|---|
| `MOODLE_SITE_FULLNAME` | Your platform's display name, e.g. `"Greenfield School E-Learning"` |
| `MOODLE_SITE_SHORTNAME` | Short form for menus, e.g. `GSE` |
| `MOODLE_TIMEZONE` | e.g. `Europe/Berlin`, `Asia/Tokyo` |
| `MOODLE_SMTP_*` | Outgoing email — see [Outgoing email](#outgoing-email) below; fine to leave empty at first |

Save and exit (in nano: `Ctrl+O`, `Enter`, `Ctrl+X`).

> **Keep `.env` safe.** It contains all your passwords. It is deliberately
> excluded from git, so back it up somewhere private (password manager,
> encrypted drive) — you need it to rebuild the server.

### Step 4 — Start the platform

```sh
docker compose up -d --build
```

What happens now (5–15 minutes on the first run):

1. Docker downloads the base images and builds the Moodle image
   (downloads the current Moodle 5.3.x release).
2. MariaDB initializes the empty database.
3. The moodle container waits for the database, then **installs Moodle
   automatically** — watch it:

   ```sh
   docker compose logs -f moodle
   ```

   Wait for the line:

   ```
   [moodle-stack] Moodle installed. Log in as 'admin' with the password from your .env.
   ```

   (`Ctrl+C` stops watching the logs, not the containers.)
4. Caddy requests the HTTPS certificate the first time the site is opened.

Check that everything is up:

```sh
docker compose ps    # all services "running", moodle eventually "healthy"
```

### Step 5 — Log in and look around

Open `https://your-domain` and sign in with `MOODLE_ADMIN_USER` /
`MOODLE_ADMIN_PASSWORD`. Recommended first stops inside Moodle (all under
**Site administration**):

- **Notifications** — should show no pending issues.
- **Reports → System status** — everything "OK", including **Router**.
- **Reports → Security checks** — review the list; **Public paths** should
  be "OK". Some entries (e.g. password policy, guest access) are site
  decisions only you can make.
- **Server → Environment** — everything green.
- **Server → Email → Outgoing mail configuration → Test outgoing mail
  configuration** — once you've configured SMTP.

### Step 6 — Set up backups (please don't skip this)

A working site without backups is a time bomb. This repo ships a one-command
backup:

```sh
./scripts/backup.sh
```

It writes a database dump and a files archive into `backups/`. Run it on a
schedule, e.g. daily at 03:30, via the server's crontab:

```sh
crontab -e
# add this line (adjust the path):
30 3 * * * /home/yourname/moodle_docker/scripts/backup.sh >> /home/yourname/moodle_docker/backups/backup.log 2>&1
```

Then regularly copy the `backups/` folder **off the server** (e.g. with
`scp`/`rsync` to your computer, or to cloud storage). Restoring is one
command too — see below.

### Outgoing email

Moodle needs an email route for password resets and notifications. Fill the
`MOODLE_SMTP_*` block in `.env` with the SMTP details of any mailbox or
email service you control, then apply with `docker compose up -d`.

⚠️ **Cloud servers usually have outgoing SMTP blocked** by the provider
(silently — connections just time out). See
[docs/server-setup.md](docs/server-setup.md#a7-important-outgoing-email-is-probably-blocked)
for the two ways around it.

---

## 4. Everyday operations

All commands run in the project folder (where `docker-compose.yml` lives).

| Task | Command |
|---|---|
| See status of all services | `docker compose ps` |
| Watch logs (all / one service) | `docker compose logs -f` / `docker compose logs -f moodle` |
| Restart everything | `docker compose restart` |
| Stop the site | `docker compose down` (data is kept) |
| Start it again | `docker compose up -d` |
| Back up database + files | `./scripts/backup.sh` |
| Restore a backup | `./scripts/restore.sh backups/db-<stamp>.sql.gz backups/moodledata-<stamp>.tar.gz` |
| Apply a changed `.env` | `docker compose up -d` |
| Moodle maintenance mode on/off | `docker compose exec -u www-data moodle php admin/cli/maintenance.php --enable` (or `--disable`) |
| Reset a forgotten admin password | `docker compose exec -u www-data moodle php admin/cli/reset_password.php` |
| Purge Moodle caches | `docker compose exec -u www-data moodle php admin/cli/purge_caches.php` |
| Run Moodle's health checks from the shell | `docker compose exec -u www-data moodle php admin/cli/checks.php` |

**HTTPS certificate renewal:** automatic, roughly 30 days before expiry.
There is genuinely nothing to do.

---

## 5. Updating Moodle

**Back up first** (`./scripts/backup.sh`), then:

### Patch updates within 5.3.x (e.g. 5.3.1 → 5.3.2 — do this regularly)

The image build always fetches the newest 5.3.x release, so:

```sh
docker compose build --no-cache moodle
docker compose up -d
```

On start, the stack detects the new code and applies the database upgrade
automatically (you'll see it in `docker compose logs -f moodle`).

If you pinned an exact version in `.env` (e.g. `MOODLE_TARBALL=moodle-5.3.1.tgz`),
change it to the new release first. Moodle names the first release of a
branch without `.0` (`moodle-5.3.tgz`); later ones are `moodle-5.3.1.tgz`,
`moodle-5.3.2.tgz`, and so on.

### Upgrading from Moodle 4.5

Earlier versions of this repository installed Moodle 4.5 LTS. Moodle 5.1
reorganised its files (everything browsers may see moved into a `public/`
folder), and this repository changed with it. Moodle supports upgrading
straight from 4.5 to 5.3, and your courses, users and files come along.
Plan about 30 minutes; the site is only down for the few minutes the
database upgrade takes.

1. **Back up, and copy the backup off the server.**

   ```sh
   ./scripts/backup.sh
   ```

   If your provider offers server snapshots, take one as well.

2. **Check your plugins.** Each additional plugin needs a release that
   supports Moodle 5.3. If you baked plugins into the `Dockerfile`, change
   their target folder from `/var/www/html/<type>/<name>` to
   `/var/www/html/public/<type>/<name>` and switch them to their 5.3 branch.

3. **Get the new version of this repository:**

   ```sh
   git pull
   ```

   (If git refuses because you changed the `Dockerfile`, run `git stash`,
   `git pull`, `git stash pop`, then fix any conflict it reports.)

4. **Update the build settings in `.env`.** Your `.env` still names 4.5,
   and its values take priority over the new defaults. Change these three
   lines to:

   ```ini
   MOODLE_BRANCH=503
   MOODLE_TARBALL=moodle-latest-503.tgz
   IMAGE_TAG=5.3
   ```

   If you forget this step, the build stops with an error pointing here.
   Your running site is not affected by that.

5. **Build and start:**

   ```sh
   docker compose up -d --build
   docker compose logs -f moodle
   ```

   The moodle container finds your existing site and upgrades its database
   (`[moodle-stack] Existing installation found — checking for pending
   upgrades...`, followed by a long list of plugin names). Wait until the
   log shows `Command line upgrade from 4.5... to 5.3... completed
   successfully.` and Apache has started.

6. **Check** the site as in [Step 5](#step-5--log-in-and-look-around).
   Moodle 5.3 has a new look in places; nothing is lost.

Keep the backup from step 1 until you are happy with the upgraded site:
an upgraded database cannot be used by Moodle 4.5 again.

### Major upgrades (the next Moodle version — deliberate, read release notes first)

1. Read the new version's release notes and check that your plugins
   support it.
2. Check whether this repository has been updated for that version.
3. In `.env`, set the new branch. The branch number is the version without
   the dot, e.g. 6.0 → `600`:

   ```ini
   MOODLE_BRANCH=600
   MOODLE_TARBALL=moodle-latest-600.tgz
   IMAGE_TAG=6.0
   ```

4. Back up, then rebuild and restart as for a patch update.

A new `IMAGE_TAG` keeps the previous image on the server, which makes going
back quicker. Plan a few minutes of downtime: the site stays up on the old
version until the rebuilt container starts and upgrades the database.

---

## 6. Adding plugins

Plugins are baked into the image at build time instead of being installed
through the admin UI — that way, every fresh deployment of your repository
has exactly the same plugin set ("infrastructure as code").

Open the [`Dockerfile`](Dockerfile), find the *"Optional: bake plugins"*
block in Stage 1, and follow the example there. Since Moodle 5.1, plugins
go inside the `public/` folder (`/var/www/html/public/<type>/<name>`). Then:

```sh
docker compose build moodle && docker compose up -d
```

The automatic upgrade on start registers the new plugin.

---

## 7. Troubleshooting

**The site shows a certificate error / Caddy can't get a certificate**
- Your domain isn't pointing at the server yet. Check with
  `ping your-domain` from your own computer.
- Port 80 is not reachable from the internet (firewall or router). The
  certificate handshake *requires* port 80.
- Check Caddy's own logs: `docker compose logs caddy`.
- Tried too often? Let's Encrypt allows 5 certificates per domain per week.
  Wait, or test with `MOODLE_DOMAIN=localhost` in the meantime.

**`docker compose up` fails with "Set DB_PASSWORD in .env"-style errors**
- You haven't created `.env` (`cp .env.example .env`) or left a required
  value empty. The message names the exact variable.

**The build fails with "... is older than Moodle 5.1"**
- Your `.env` still asks for Moodle 4.5. See
  [Upgrading from Moodle 4.5](#upgrading-from-moodle-45), step 4.

**Browser warning on https://localhost**
- Expected. Public certificates for `localhost` don't exist, so Caddy signs
  one itself. Click "Advanced" → "Proceed". Real domains get real
  certificates automatically.

**"This site is undergoing maintenance" forever / upgrade interrupted**
```sh
docker compose exec -u www-data moodle php admin/cli/upgrade.php --non-interactive
docker compose exec -u www-data moodle php admin/cli/maintenance.php --disable
```

**Moodle pages load without styling or links point to http://**
- `MOODLE_DOMAIN` in `.env` doesn't match the address in the browser.
  Fix `.env`, then `docker compose up -d`.

**"Router" shows an error under Reports → System status**
- On a localhost test site this is expected (see
  [section 2](#2-optional-try-it-on-your-own-computer-first)). On a real
  server, check that `https://your-domain/api/rest/v2/openapi.json` opens
  in your browser, and that you didn't replace `moodle/config.php` or
  `moodle/apache-vhost.conf` with older copies.

**Emails never arrive**
- SMTP not configured (`MOODLE_SMTP_HOSTS` empty), wrong credentials, or —
  on cloud servers — outgoing SMTP blocked by the provider. Test inside
  Moodle: Site administration → Server → Email → Test outgoing mail
  configuration. See [Outgoing email](#outgoing-email).

**The first start seems stuck**
- A first run legitimately takes 5–15 minutes (image build + database
  install). Watch `docker compose logs -f moodle` — as long as lines keep
  appearing, let it work. Do not stop the container during
  "installing Moodle now".

**Where is my data? Will `docker compose down` delete it?**
- No. All data lives in named Docker volumes (`db_data`, `moodledata`) that
  survive `down`, rebuilds and updates. Only `docker compose down -v`
  deletes volumes — never run it on a production site.

**I changed something in caddy/Caddyfile or a file in moodle/ — nothing happened**
- Those files are baked into the images. Apply changes with
  `docker compose up -d --build`.

---

## 8. How it works

Repository layout:

```
.
├── docker-compose.yml      the four services and how they connect
├── Dockerfile              multi-stage build: Moodle image + Caddy image
├── .env.example            template for your configuration (copy to .env)
├── caddy/
│   └── Caddyfile           reverse proxy + automatic HTTPS rules
├── moodle/
│   ├── config.php          Moodle config — reads everything from .env values
│   ├── apache-vhost.conf   Apache site: serves only public/, enables the router
│   ├── entrypoint.sh       first-run auto-installer / auto-upgrader
│   └── php-overrides.ini   PHP limits + opcache/JIT performance tuning
├── scripts/
│   ├── backup.sh           one-command backup (database + files)
│   └── restore.sh          one-command restore
└── docs/
    ├── server-setup.md     preparing a cloud or physical server from zero
    └── cloud-init.yaml     optional: fully automatic server provisioning
```

Inside the moodle image, Moodle 5.3 is laid out like this:

```
/var/www/html/            project root — never reachable from a browser
├── config.php            from moodle/config.php
├── admin/cli/            command-line tools (upgrade, cron, maintenance, ...)
├── vendor/               third-party PHP libraries
└── public/               the webroot: the only folder Apache serves
    ├── r.php             Moodle's router (newer pages and the REST API)
    └── ...               course/, mod/, theme/, plugins, ...
/var/www/moodledata/      uploaded files and caches (Docker volume)
```

Design choices, briefly:

- **Caddy instead of certbot + Apache SSL config**: certificate issuance and
  renewal become a non-event instead of a recurring manual task. Only Caddy
  is exposed to the internet; Moodle and MariaDB are reachable solely on the
  internal Docker network.
- **Only `public/` is web-reachable**: Moodle's configuration, libraries and
  command-line tools sit outside the webroot. Files inside `public/` that
  browsers never need (developer notes, test fixtures) return 404 as well,
  which is exactly what Moodle's own security check looks for.
- **Everything configurable lives in `.env`**: `config.php` reads its values
  from environment variables, so the same images run unchanged on any
  server. Required values are enforced with clear error messages.
- **Moodle code baked into the image, data on volumes**: updating Moodle is
  "rebuild the image"; your database and files are never inside a container.
- **A dedicated cron service**: Moodle's scheduled tasks run every minute
  from day one, the way Moodle expects — no host crontab to forget.
- **PHP tuned for Moodle**: the default opcache is too small for Moodle's
  code base and slows every page; `moodle/php-overrides.ini` sizes it
  properly and turns on PHP's JIT compiler.

## License

[MIT](LICENSE) — use it, fork it, adapt it for your school or organization.
