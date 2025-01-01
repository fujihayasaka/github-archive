# Differences between Newsies and Notifyd

## CC Field
* Notifyd does not list the user's email in the `CC` field, while Newsies lists the emails when a user [participates in the thread](https://github.com/github/github/blob/e8119525ec9eecfd44ad8038deb4a459efb483f1/lib/newsies/emails/message.rb#L218-L222). A [defined list of reasons](https://github.com/github/github/blob/e8119525ec9eecfd44ad8038deb4a459efb483f1/lib/newsies/emails/message.rb#L572) determines participation. However, the [docs page](https://docs.github.com/en/account-and-profile/managing-subscriptions-and-notifications-on-github/setting-up-notifications/configuring-notifications) notes that the user's email is included when the user is subscribed to the thread.
* Notifyd may include multiple email-formatted reasons in the `CC` field, while Newsies only includes one.

