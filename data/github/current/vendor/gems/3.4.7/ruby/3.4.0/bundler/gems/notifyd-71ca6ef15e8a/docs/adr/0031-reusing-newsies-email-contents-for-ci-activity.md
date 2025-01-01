# 31. Reusing Newsies email contents for CI activity emails

Date: 2022-07-18

## Status

Accepted

## Context

While finishing up the migration of email delivery for CI activity a couple of related discussions happened:
- Whether to use a [new design][1] or reuse the existing design for these emails.
- In the latter case, whether to [reuse or rewrite][2] existing content from Newsies.

## Decision

- Initially, CI activity emails will have content parity in the new platform.
- Existing email content from Newsies will be reused instead of reimplemented.

## Consequences

- A raw layout will be provided to support rendering of emails in dotcom.
- A bridge will be used to make notifyd and newsies data models compatible for email rendering.
- New email design will require a better layout / templating system support in notifyd, which is left for a future iteration.

[1]: https://github.com/github/notifyd/issues/1369
[2]: https://github.com/github/notifyd/issues/1398

