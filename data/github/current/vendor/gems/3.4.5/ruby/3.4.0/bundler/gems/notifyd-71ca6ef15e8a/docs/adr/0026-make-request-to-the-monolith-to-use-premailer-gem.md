# 26. Make request to the monolith to use premailer gem

Date: 2022-03-31

## Status

Accepted

Amends [3. Minimise requests from the notifications service back to the monolith](https://github.com/github/notifyd/blob/main/docs/adr/0003-minimise-requests-from-the-notifications-service-back-to-the-monolith.md)[](https://github.com/github/notifyd/blob/main/docs/adr/0018-make-request-to-monolith-for-notification-specific-auth-checks.md#context)

## Context

Notifyd is now [supporting html templates](https://github.com/github/notifyd/issues/687) for email deliveries. A problem we had in enabling this feature was finding a proper way to process the CSS:

<img width="792" alt="154498263-79054af0-a20b-4185-98ad-c422cf196ba7" src="https://user-images.githubusercontent.com/8514581/161042404-0e0e0cf9-3bd3-4dcd-8ed9-e59ec143c037.png">

We are using [Primer library classes](https://primer.style/) to build layouts that follow [Primer email layout styles](https://thehub.github.com/engineering/development-and-ops/email/#the-primer-email-layout) that uses the monolith.

## Decision

We proposed different solutions: https://docs.google.com/document/d/1cnsQoaeaN7AT_CRPFpi-iK-xNYUJUG5o9ZxQ5BmYUKE/edit#heading=h.ye7ih9xgl3b
- Solution 1: Use the full Primer css in emails
- Solution 2: Create a template microservice
- Solution 3: Request to the monolith to use premailer gem 👈
- Solution 4: Using go-premailer to generate html files
- Solution 5: Use a node script with juice library
- Solution 6: Prerender emails with styles inline
- Solution 7: Discard css with purge js using node

As we were looking for a **temporary**, easy, reliable and low-risk solution, we decided to go with **Solution 3: Request to the monolith to use [premailer gem](https://github.com/premailer/premailer)**. 

## Consequences

This is a temporary solution as we want to decouple notifyd logic from the monolith and [minimise requests back to the monolith](https://github.com/github/notifyd/blob/main/docs/adr/0003-minimise-requests-from-the-notifications-service-back-to-the-monolith.md). At some point we will want to remove these dependencies.

### Benefits

- It is not necessary to enlarge the scope of enabling label subscriptions feature.
- Library is already being used by monolith for emails.

### Drawbacks

- We are continuing to rely on the monolith for processing styles.
- It will impact performance of the delivery pipeline.
