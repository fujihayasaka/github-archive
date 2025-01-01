# Approach to migrating thread and repository notifications from Newsies to Notifyd

## Current state

When we talk about the activity on the thread in GitHub Newsies notifies user in two cases:

1. User is explicitly mentioned (either individually or as part of a team).
2. User is subscribed to notification.

Subscriptions in their turn are divided into manual subscriptions (user explicitly subscribed) and auto-subscriptions.

Examples of manual subscriptions:

1. User manually subscribes to a thread
2. User watches all activity in a repository
3. User subscribes to all activity on pull requests in a repository

Examples of auto-subscription:

1. When user creates an issue they're automatically subscribed to a thread as an author and will be receiving all notifications about comments.
2. When user is mentioned they're automatically subscribed for the subsequent activity on a thread.
3. When user comments in a thread they're automatically subscribed as a commenter.

Every time user modifies the thread Newsies decide if new auto-subscriptions shall be created. Auto-subscription is an actual entry in one of the newsies subscriptions table.

When event happens (someone commented on a thread as an example) Newsies uses subscriptions to make the list of the recipients.

Below is the diagram of the auto-subscription flow.

![image](https://user-images.githubusercontent.com/1885174/184652127-9f32186d-aebd-4bc0-9e52-bae9544037bd.png)


## Migrating auto-subscriptions

The main question is: does it make sense to replicate auto-subscriptions logic to Notifyd or we can achieve **almost** the same behavior in other ways?

What if we cross-out auto-subscription part completely?

Below is the Notifications flow diagram without auto-subscription.

![image](https://user-images.githubusercontent.com/1885174/184662341-10951812-be77-4bd7-a37b-da72a55c4b3a.png)


When user interacts with subject be this issue, pull request or other, we do not implicitly subscribe users to the events on a subject thread like we did previously.

Instead, we let the integrator decide who should receive the notification at the point of time when event happens. The integrator will form the list of explicit recipients based on the thread data. Integrator can calculate a list of thread participants that need to be notified about certain event. For example, participants may include: thread author, commenters, assignees, users mentioned in comments or a body, users that are members of mentioned teams etc. Thread notification configuration is described [here](https://gist.github.com/mariorod/f90478023102bd9be6cd0d9cb86ba9b8).

The integrator sends the list of recipients to Notifyd as explicit recipients.

### Advantages

If we adopt this approach we will get the following advantages:

1. Significant reduction of the data we need to migrate and store in Notifyd.
If we cut auto-subscriptions we get rid of majority of thread subscriptions we currently have in Newsies which means the Notiyd storage size will be reduced. Also, we can get rid of data sync part for auto-subscriptions.
2. Integrator and Notifications team have control over notifications sent to users.
If we make a decision on who should receive notification for the event not based on stored auto-subscriptions but based on some centralized logic we have full control of the notifications. For example, we can decide that we no more going to notify users that are members of the mentioned team.

### Disadvantages

1. The main disadvantage of described approach is that new behavior might not fully match the old one.
For example, if we decide to exclude mentioned users from thread participants they will no longer receive notifications on the thread they already subscribed to.
This behavior change should be properly communicated to the users via public channels, for example [GitHub changelog](https://github.blog/changelog/)

2. Calculating list of participants may be expensive. Along with dropping auto-subscriptions we need to drop some notifications workflows as well.
For example, the following workflows would be problematic to implement without having auto-subscriptions:

- If user is mentioned in a thread, they'll be notified on a subsequent activity on this thread.
- If team is mentioned on a thread, its members will be notified on a subsequent activity on this thread.

These workflow require deep look into the all thread comments markdown which is really expensive for long threads. Auto-subscriptions allow us to cache the information about participants that were mentioned or team-mentioned. Auto-subscriptions allow us to cache this information.

The diagram below shows the impact of removing auto-subscriptions for Gists:

![image](https://user-images.githubusercontent.com/1885174/186149138-746559d8-befb-4dd1-9857-ec991ac936eb.png)


## Opting out from receiving notifications

In case user does not want to receive notifications for example, for the threads he authored, he will be able to disable them explicitly in Notification settings.

Same happens when user does not want to be subscribed to a particular thread anymore. User will be able to ignore a thread and it will be translated into Notifyd setting that disables notifications on a thread.

## Migrating manual subscriptions

Manual subscriptions will be migrated as Notifyd subscriptions.

Below is the diagram that shows what happens when user manually subscribes to a certain thread.

![image](https://user-images.githubusercontent.com/1885174/184657900-d20c6594-8457-48ea-b4ca-7dc3cd8672af.png)

In the same way we will be treating repository subscriptions: watch all activity and thread type subscriptions as a manual subscription and it will be saved explicitly to a database.

## Subject-based migration

We adopt subject-based approach to migrating Newsies subscriptions to Notifyd.

In order to avoid notification duplicates we need to fully migrate notification related to the subject (for example, issue) to Notifyd.

In order to migrate the subject we need to migrate:

1. All the "watch all repository activity" subscriptions (list subscriptions in Newsies) and thread type subscriptions.
2. Migrate all the manual thread subscriptions.
3. Implement delivery pipeline for the subject.

First item must be implemented for all the subjects that belong to a repo like issues. Some subjects belong to a user or organization (like Gists) therefore we need to implement only 2) and 3).


## Conclusion

Deprecating auto-subscriptions will allow us to get rid of outdated and unwanted scenarios that we currently have and concentrate on the behavior and features of a new system instead of thinking of replicating 1 to 1 Newsies behavior and data.
