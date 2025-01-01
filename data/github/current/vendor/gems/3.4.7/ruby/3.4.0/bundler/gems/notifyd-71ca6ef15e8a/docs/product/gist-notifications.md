# Gist Notifications

## Current state

Currently user is automatically subscribed to a Gist thread in the following cases:

1. User is an author.
2. User is mentioned in one of the comments in a thread.
3. User commented on a Gist.

User can manually subscribe to a Gist by clicking "Subscribe" button on a Gist page.

User that have subscriptions are notified whenever someone comments on a Gist.

Subscriptions to Gists are not displayed on github.com/notifications/subscriptions page. This page shows only subscriptions to entities that belong to repo. Gist can belong only to a user or an organization.

Team cannot be mentioned in a Gist comment so there are no notifications associated with team mentions.

[This query](https://data.githubapp.com/sql/0e461544-e9e9-444d-96a8-5be7b381a3ba) summarizes all the reasons we currently have for Gists subscriptions.

![image](https://user-images.githubusercontent.com/1885174/185620529-304e1e39-bfc4-4bf4-a28c-5af958c42aa1.png)

Gists owners are either user or organizations. Gist can belong to an organization only in case this organization used to be a user and was later converted to an organization. New Gists cannot be created in an org.

### Unsubscribe

User has three options to unsubscribe from Gist notifications:

1. Click unsubscribe button on Gist page
2. Click unsubscribe link in the notification email
3. Unsubscribe using email client, in this case unsubscribe link from List-Unsubscribe email header will be used.

## Product change

In the epic to move Gist Notifications to Notifyd we decided to [drift away from the auto-subscriptions concept](https://github.com/github/notifyd/pull/1558).

This means that we will not automatically create a subscription in cases mentioned above. We will create a subscription only in case user clicks "Subscribe" button on the thread page, i.e. explicitly expresses the intent to receive notifications from the thread.

But user will keep receiving notifications for certain events in the thread even if user is not explicitly subscribed:

1. If user is the author of a Gist, they'll receive notifications if someone comments on a Gist.
2. If user has previously commented on a Gist, they'll receive notifications on all the subsequent comments.
3. If the user is explicitly mentioned in a comment they'll receive a notification for this particular comment (but not the subsequent ones).
4. If someone updated a comment and a change contains a user mention the mentioned user will receive notification for the updated comment.

User will be able to unsubscribe from Gist thread using options listed above. When user unsubscribes this means we will not send any notifications for the user thread.