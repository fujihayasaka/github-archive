# Enable the possibility for end users to subscribe to a label in a repository

## Problem statement

We’d like to provide users with an interface to subscribe/unsubscribe to/from a label.

We're aiming to implement the following scenarios:

- Users can choose labels they want to subscribe to in a certain repository. When a user is subscribed to a label, they will get notified when a comment is added to any issue marked with this label.
- Users can remove labels they do not want to be subscribed to anymore.


## Context

As part of our effort to support [LLVM migration to issues](https://github.com/github/planning-tracking/issues/547) and after we implemented prototype for [sending emails with Notifyd](https://github.com/github/planning-tracking/issues/585) and [added subscriptions support](https://github.com/github/planning-tracking/issues/633). Next step is going to be adding a possibility for customers to subscribe/unsubscribe for email notification when the issue with a certain label is commented on.

Currently we can be notified about the scenario “comment is added to an issue with a label” but we cannot create a subscription itself.
This should be possible after this epic is implemented.

### Current Notifyd notifications flow

![image](https://user-images.githubusercontent.com/1885174/146918202-2f700d7c-b166-4daa-ac7e-f55beb9bb529.png)

Currently the notify-consumer in `Notifyd` gets recipients from two sources: explicit mentions in the notify message itself and subscribers stored in database.

### Expected outcome

Via UI users can store subscriptions that will be used by the existing notifications flow to notify users via email channel.

![image](https://user-images.githubusercontent.com/1885174/146965849-245e1cff-2aa6-4ba2-8aa0-c3ece80e4a0b.png)


## Goals and objectives

1. API in Notifyd to:
    - store a subscription
    - fetch subscriptions for a certain user and topics
2. UI in monolith (github/github) to subscribe to labels (as well as to remove subscription to labels).
3. A tool (library) to integrate monolith with Notifyd subscriptions API.

Below is the design mockup.

[![Video](https://user-images.githubusercontent.com/1885174/146945556-6b5abe57-876d-418e-ab3d-3977ab50735e.png)](https://user-images.githubusercontent.com/1885174/146945022-28a84251-72ba-49ae-b005-fe662498a343.mov)


## Assumptions

Q: What about performance?
A: We're not concerned yet about optimising performance.

Q: Can we choose multiple labels?
A: Yes, users can subscribe to multiple labels. When a user subscribes to multiple labels and the issue with either one of them is commented they will get notified.

Q: Can we create label filters for discussions and other entities?
A: Currently we are only supporting issues. From the UI perspective we want to support only issues for the moment, but in the future we want support everything.

Q: How existing notifications (backed by Newsies) and notifications for label subscriptions (backed by Notifyd) will co-exist?
A: Notification synchronization with Newsies is not in the scope for this epic. In other words, if a user is watching the repo already and decides to subscribe to a label, for some events they might get duplicated notifications.

Q: To whom we're planning to ship this?
A: We're going to only team ship it (make available for notifications team and staff members that would like to voluntarily opt in).

## Guiding Principles

* Notifyd shouldn't incorporate domain logic of integrators.
* API should be clear for integrators.
