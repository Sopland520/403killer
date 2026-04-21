<div align="center">

```
██╗  ██╗  ██████╗  ██████╗ ██╗  ██╗██╗██╗     ██╗     ███████╗██████╗
██║  ██║ ██╔═████╗╚════██╗ ██║ ██╔╝██║██║     ██║     ██╔════╝██╔══██╗
███████║ ██║██╔██║  █████╔╝ █████╔╝ ██║██║     ██║     █████╗  ██████╔╝
╚════██║ ████╔╝██║  ╚═══██╗ ██╔═██╗ ██║██║     ██║     ██╔══╝  ██╔══██╗
     ██║ ╚██████╔╝ ██████╔╝ ██║  ██╗██║███████╗███████╗███████╗██║  ██║
     ╚═╝  ╚═════╝  ╚═════╝  ╚═╝  ╚═╝╚═╝╚══════╝╚══════╝╚══════╝╚═╝  ╚═╝
```

**Advanced HTTP 403 Bypass Tool**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
![Bash](https://img.shields.io/badge/Shell-Bash-green)
![Platform](https://img.shields.io/badge/Platform-Linux%20%7C%20macOS-blue)

> If this tool helped you find a bug — drop a ⭐ it keeps the project alive!

</div>

---

## What is 403Killer?

403Killer is a Bash script that automates HTTP 403 Forbidden bypass techniques. It fires 80+ tests across 6 attack categories, compares every response to a baseline, and flags potential bypasses in real time with an animated spinner and color-coded output.

Designed for **bug bounty hunters** and **pentesters** working on authorized engagements.

---

## Features

- **80+ bypass techniques** across 6 categories
- **Baseline comparison** — only flags responses that actually differ
- **Authenticated testing** — inject session cookies or auth headers on every request (privilege escalation testing)
- **Animated Braille spinner** per request with live feedback
- **Color-coded output** — green for bypass, yellow for redirect/diff, red for blocked
- **Confirmed bypass summary** at the end
- **Wayback Machine** lookup for archived versions
- **Rate limiting** option to stay under radar
- **No external dependencies** — only `curl` and standard Unix tools

---

## Attack Categories

| # | Category | Techniques |
|---|----------|-----------|
| 1 | **Path Manipulation** | dot/slash tricks, semicolon bypasses (Spring/Tomcat), double URL encoding, overlong UTF-8, null bytes, IIS ADS/short names, extension spoofing, case swap |
| 2 | **IP Spoofing Headers** | X-Forwarded-For, X-Real-IP, X-Client-IP, CF-Connecting-IP, True-Client-IP, Forwarded, Referer, and 10 more + multi-header combos |
| 3 | **URL Rewrite Headers** | X-Original-URL, X-Rewrite-URL, X-Override-URL |
| 4 | **Host Header Manipulation** | Host, X-Forwarded-Host, X-Host, X-Forwarded-Proto |
| 5 | **HTTP Method Override** | HEAD, OPTIONS, TRACE, PUT, PATCH, DELETE, X-HTTP-Method-Override, HTTP/1.0 downgrade, method+IP combos |
| 6 | **Wayback Machine** | Check for archived/cached versions of the blocked resource |

---

## Installation

```bash
git clone https://github.com/Sopland520/403Killer.git
cd 403Killer
chmod +x 403killer.sh
```

**Requirements:** `curl` (installed on virtually every Linux/macOS system)

---

## Usage

```bash
./403killer.sh <URL> <path> [options]
```

| Option | Description |
|--------|-------------|
| `-H "Header: value"` | Add a global header to all requests (repeatable) |
| `-c "name=value"` | Shorthand for `Cookie:` header |
| `-d <ms>` | Delay between requests in milliseconds |

---

## Examples

**Basic — anonymous target:**
```bash
./403killer.sh https://example.com admin
```

**Authenticated — session cookie** *(test privilege escalation from a normal account)*:
```bash
./403killer.sh https://example.com api/admin -c "session=abc123def456"
```

**Authenticated — JWT Bearer token:**
```bash
./403killer.sh https://example.com api/admin -H "Authorization: Bearer eyJhbGci..."
```

**Multiple headers + rate limiting:**
```bash
./403killer.sh https://example.com api/admin \
  -H "Cookie: session=abc123" \
  -H "X-CSRF-Token: tok_xyz789" \
  -d 200
```

---

## Output

```
   ✔ [200]    4821b  /%2e/admin                 ◀◀ BYPASS!
   ↪ [302]    0b     /;/admin                   ◀ DIFF
   ✖ [403]    1024b  X-Forwarded-For: 127.0.0.1
   · [404]    512b   /admin.php

   SUMMARY  (83 techniques tested · baseline: [403] 1024b)

   [!] 1 HTTP bypass(es) confirmed:

   ✔  [200]  /%2e/admin  (4821b)
```

---

## Disclaimer

This tool is intended for **authorized security testing only** — bug bounty programs, penetration testing engagements, and CTF challenges. Do not use it against systems you do not have explicit permission to test. The author is not responsible for any misuse.

---

## License

MIT — see [LICENSE](LICENSE)

---

<div align="center">

Made by **Sopland**

**[⭐ Star this repo](../../stargazers) if it helped you pop a 403!**

</div>
