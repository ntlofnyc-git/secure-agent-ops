# Security

These scripts change firewalls, SSH and web-server config. Read each one before running it,
apply it to one box first, and keep an out-of-band console (your provider's KVM/rescue mode)
handy the first time you apply firewall or SSH changes.

Found a flaw in a script here (a guard that can be bypassed, a rule that doesn't match what it
claims)? Please open a private security advisory on this repo rather than a public issue.

All names, numbers, domains and IP addresses in this repo are fictional. IPs come from the
RFC 5737 / RFC 3849 documentation ranges.
