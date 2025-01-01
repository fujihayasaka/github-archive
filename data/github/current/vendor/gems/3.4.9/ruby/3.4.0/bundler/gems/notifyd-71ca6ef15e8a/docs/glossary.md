# Notifications glossary

This glossary is a list of terms that are related to notifications together with examples of their use:

- Notification: An event that is worth the attention of a GitHub user.
- Subject: The entity to which a notification refers. For example an `Issue` or an `IssueComment`.
- Trigger: The action that produces the notification. E.g. creating an `IssueComment` that mentions someone.
- Actor: The entity whose action produces a _notification_.
- Recipient: The user who will receive the _notification_.
- Subscription: A list of rules set by a user defining the activity for which they want to receive a _notification_.
- Channel: The delivery method that we will use to deliver a notification to the _Recipient_.
- Consumer: a process that runs on a server, in our case it is written in Go and reads messages from a _Source_.
- Source: an entity on a _Consumer_ that loops over the messages on a kafka partition and handles them performing some kind of operation.
- Handler: an entity that receives the messages read from a _Source_ and performs some operation with them as an input.

## Examples

### A push notification for an @mention on an issue comment

- Subject: An issue comment
- Trigger: Creating a comment
- Actor: The user authoring the issue comment
- Recipient: The user mentioned by the @mention
- Channel: Push notification

### An email with a security alert for a dependency

- Subject: The repo in which the security issue has been detected.
- Trigger: Dependabot detecting that a dependency has a security issue.
- Actor: GH / Dependabot ??
- Recipient: A User that is subscribed to security alerts
- Channel: Email

### A web notification with a review request

- Subject: The pull request to review
- Trigger: Requesting a review
- Actor: The user that requests the review
- Recipient: The user to whom the review is requested
- Channel: Web notifications