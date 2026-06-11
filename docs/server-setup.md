# Preparing a server for the Moodle stack

This guide takes you from "I have nothing" to a machine that is ready for
`docker compose up`. Follow **Option A** for a rented cloud server (the
usual choice for a public site) or **Option B** for a physical machine you
own. The final section applies to both.

If you just want to test on your own computer first, you don't need any of
this — see ["Try it on your own computer"](../README.md#2-optional-try-it-on-your-own-computer-first)
in the README.

---

## Option A — Cloud server (recommended for a public site)

### A1. Choose a provider and size

Any provider that rents Linux virtual machines works: Hetzner, DigitalOcean,
Vultr, Linode, OVH, AWS Lightsail, etc. A sensible starting size for a
small-to-medium Moodle (tens to a few hundred active users):

| Resource | Minimum | Comfortable |
|----------|---------|-------------|
| RAM      | 2 GB    | 4 GB        |
| CPU      | 2 vCPU  | 2–4 vCPU    |
| Disk     | 40 GB   | 80 GB+ (course files add up) |

Choose **Ubuntu 24.04 LTS** as the operating system. You can resize most
cloud servers later, so start small.

### A2. Create an SSH key (on your own computer)

SSH keys let you log in to the server securely without a password. If you
have never made one:

```sh
ssh-keygen -t ed25519 -C "your-email@example.org"
# Press Enter to accept the default location (~/.ssh/id_ed25519).
# Choosing a passphrase is recommended but optional.

cat ~/.ssh/id_ed25519.pub
```

The `cat` command prints your **public** key (one line starting with
`ssh-ed25519`). You will paste this into the provider's website when
creating the server. The **private** key (the file without `.pub`) stays on
your computer — never share or upload it.

### A3. Create the server

In your provider's control panel:

1. Create a new server / instance / droplet with **Ubuntu 24.04 LTS**.
2. Add your **public SSH key** when asked.
3. (Optional, but a nice shortcut) If the provider has a "user data" or
   "cloud-init" field, paste the contents of [`cloud-init.yaml`](cloud-init.yaml)
   after replacing every `<PLACEHOLDER>` in it. That file automatically
   creates your user, configures the firewall, hardens SSH and installs
   Docker — letting you skip steps A4–A6.
4. Note the server's **public IP address** once it is running.

### A4. First login and a non-root user

```sh
ssh root@YOUR_SERVER_IP
```

Working as `root` all the time is risky; create your own user:

```sh
adduser yourname                 # pick a password when asked
usermod -aG sudo yourname        # allow it to run admin commands
rsync --archive --chown=yourname:yourname ~/.ssh /home/yourname  # copy SSH access
exit
ssh yourname@YOUR_SERVER_IP      # log back in as the new user
```

### A5. Firewall

```sh
sudo ufw allow OpenSSH
sudo ufw allow 80/tcp      # HTTP  (needed for the certificate handshake)
sudo ufw allow 443/tcp     # HTTPS
sudo ufw allow 443/udp     # HTTP/3
sudo ufw --force enable
sudo ufw status
```

### A6. Install Docker

```sh
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER    # run docker without sudo
```

Log out and back in (`exit`, then `ssh` again) so the group change takes
effect, then verify:

```sh
docker compose version    # should print v2.x
```

### A7. Important: outgoing email is probably blocked

Most cloud providers (Hetzner, AWS, DigitalOcean, ...) **silently block
outgoing SMTP ports (25, 465, 587)** on new accounts to prevent spam. The
block is enforced upstream — your firewall won't show it, and the symptom
is plain connection timeouts to *any* mail server.

If your Moodle must send email (password resets, notifications), either:

- open a support ticket with your provider asking them to unblock outbound
  465/587 (mention the server IP and that it's for a school LMS), **or**
- use a transactional email service with an HTTPS API (Postmark, Mailgun,
  Brevo, Amazon SES) — these are not affected by the SMTP block and usually
  offer an SMTP-over-587 endpoint that providers unblock more readily.

---

## Option B — Physical server (home / school / office)

A spare PC or mini-PC works fine. Be aware of what you're taking on
compared to a cloud server: you are responsible for power, cooling, disk
failure and the internet connection.

### B1. Install the operating system

Install **Ubuntu Server 24.04 LTS** (free, [download here](https://ubuntu.com/download/server)).
During installation, enable the OpenSSH server when asked. Then follow
steps **A5** (firewall) and **A6** (Docker) from above.

### B2. Give the machine a fixed address on your network

In your router's admin page, assign the server a **static/reserved LAN IP**
(e.g. `192.168.1.50`) so it doesn't change after a reboot. The option is
usually under "DHCP" → "Address reservation" or similar.

### B3. Forward ports from your router to the server

For people on the internet to reach your Moodle, your router must forward:

- TCP port **80** → server LAN IP, port 80
- TCP port **443** → server LAN IP, port 443
- UDP port **443** → server LAN IP, port 443 (optional, enables HTTP/3)

The setting is usually called "Port forwarding" or "Virtual server".

> **CGNAT warning:** some ISPs don't give you a real public IP (this is
> called CGNAT — common on mobile/LTE connections and some fiber providers).
> If you can't reach your site from outside even though port forwarding is
> set up correctly, ask your ISP for a public IPv4 address, or use a tunnel
> service such as Cloudflare Tunnel.

### B4. Domain name for a home connection

Home IP addresses change from time to time. Two common solutions:

- **Dynamic DNS**: services like [DuckDNS](https://www.duckdns.org) (free)
  give you a name like `myschool.duckdns.org` that follows your changing IP.
  Use that name as `MOODLE_DOMAIN`.
- **Your own domain + dynamic DNS client**: buy a domain, manage its DNS at
  a provider with an update API (e.g. Cloudflare), and run their update
  client on the server.

---

## Both options — point your domain at the server

Skip this if you used a dynamic-DNS name (it already points at you).

1. Buy a domain at any registrar (Namecheap, Porkbun, Cloudflare, ...) or
   use one you already own. A subdomain like `moodle.yourschool.org` is fine
   and free if you own `yourschool.org`.
2. In the domain's DNS settings, create an **A record**:
   - **Name/host**: `moodle` (or `@` for the bare domain)
   - **Value**: your server's public IP
3. Wait for it to take effect (minutes to a few hours), then verify from
   your own computer:

```sh
ping moodle.yourschool.org    # should answer from your server's IP
```

Only continue with the README's deployment steps once the domain resolves —
the automatic HTTPS certificate can't be issued before then.
