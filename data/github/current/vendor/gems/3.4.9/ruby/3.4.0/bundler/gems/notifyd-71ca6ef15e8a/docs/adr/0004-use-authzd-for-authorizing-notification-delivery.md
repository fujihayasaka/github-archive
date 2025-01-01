# 4. Use authzd for authorizing notification delivery

Date: 2021-03-26

## Status

Accepted

## Context

One of the key steps in the notification delivery process is authorizing that the recipient is allowed to view the content that we are about to notify them about.

In the existing system we achieve this by keeping track of the underlying model (i.e. Issue/IssueComment/Release) that the notification is about, and performing `.readable_by?` checks on the models from within the monolith.

With the added constraints of [0003-minimise-requests-from-the-notifications-service-back-to-the-monolith](./0003-minimise-requests-from-the-notifications-service-back-to-the-monolith.md) we will need an alternative solution to this problem:

- We cannot do `.readable_by?` checks on the models before triggering a notification, as we won't yet know the full list of recipients, which will be determined by the notifications system
- We cannot make requests back to the monolith to perform these checks, or we will violate [0003-minimise-requests-from-the-notifications-service-back-to-the-monolith](./0003-minimise-requests-from-the-notifications-service-back-to-the-monolith.md)
- We cannot just ignore these checks, as users expect us not to send notification content to unauthorized recipients. And particularly for email notifications, we have no way to revoke access to content once notifications are sent.
- We _could_ try to rely on the subscriptions in the notifications-platform, and hope that they are up-to-date with authorization in the monolith (i.e. try to ensure that we delete all subscriptions when a user loses access) however, given the importance of getting authorization right, and the complexity of keeping these tables up-to-date, this would be difficult, and inaccurate.
    - Additionally this would not suffice for use-cases where we don't have subscriptions in our database like direct mentions.

## Decision

We have decided that we will solve this problem by using the [authzd service](https://github.com/github/authzd) to authorize notification delivery before we send notifications. For more background discussion on this decision read https://github.com/github/notifications_platform/pull/11

This may seem like a loop hole: why can we make requests to authzd but not back to the monolith? Our reasoning is as follows:

- The authzd service exists for precisely this reason: to provide a service for authorization of resources that is external to the monolith.
- Authzd is capable of supporting our expected load<sup>[citation needed]</sup>.
- The authzd service already implements authorization policies for many of the content types we support.
- The authzd has a very simple API, consisting of essentially a single request (`.authorize?`), so it brings minimal complexity/congnitive overhead.

## Consequences

### Benefits

- We can continue to authorize all notification delivery with a high degree of confidence.
- We don't need to write our own internal authorization service, nor denormalize authorization data into our service.
- By adopting authzd ourselves, we will further demonstrate the value of authzd to github, which may help spur further development in the service, and encourage teams to expand on their own use of the service.

### Drawbacks

- Not all teams within the monolith have adopted authzd, so we may have some work to do to implement policies for features we support.
- Our uptime will be highly dependent on authzd's uptime.

### Risks

- authzd is still an actively developed service, however, the team is under-funded and may not have capacity to fill in any missing functionality in the service that we require.
