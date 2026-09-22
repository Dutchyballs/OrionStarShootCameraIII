# Security reports

Do not post credentials, private logs or exploit details in a public issue. Use GitHub's **Report a vulnerability** option under the repository's Security tab when it is available. If it is unavailable, contact the maintainer through a private channel listed on their GitHub profile; do not assume a public issue is private.

Provide affected versions, the relevant entry point, impact and a minimal reproduction. Avoid images or system dumps containing unrelated personal information. There is no guaranteed response time or commercial support commitment.

Before making the repository public, the maintainer should enable GitHub private vulnerability reporting.

## Scope

The Windows scripts forward a USB camera into WSL; setup and binding can require administrator privileges. The Linux tools access a camera device, and the INDIGO adapter runs inside the server process. Use trusted dependencies and limit server access to your intended network. Dependencies retain their own security-reporting channels.
