# Remove recipients limit from Notifyd

{:toc}

## Problem statement

We currently limit the amount of recipients to 250. If notification must be sent to more than 250 recipients we will drop the message which potentially can completely disable notifications delivery for certain events.

## Backgound

That's how our current message processing pipeline looks like:

1. We consume notification message by Notify consumer.
2. Once we get the message we determine the list of recipients we need to notify based on the data in the message. Currently we have two sources of recipients:
 - direct mentions, or recipients listed in ExplicitRecipients field of the message
 - recipients we calculate based on subscriptions stored in database: we lookup what subscriptions match the data on the message and get user identifiers from these subscriptions.
3. We perform several checks on the list of recipients:
    - authorization (using authzd) check determines what recipients are authorized to receive notification
    - notify policy check performs various checks that require data stored in monolith's database: spammy users, suspended users, whether user is ignoring notifications from repo etc.
4. We produce messages for deliver-email and deliver-mobile-push consumers for every recipient that passed checks from (3).
5. In deliver-email and deliver-mobile-push consumers we perform additional checks (this time we deal with a single recipient per message) and send email/push notification.

**Impact of the recipients limit**

Steps 1-4 of this workflow are performed by notify-consumer that deals with initial notification message. Notify consumer's job is to calculate list of recipients for the notification and this list can be unpredictably long. We used to limit the amount of recipients by 100 and recently increased it to 250, but it does not solve the problem we will face in the nearest future: if notification has to be delivered to the amount of recipients greater than the limit (whatever it is) the notification will not be delivered to anyone as we will just drop the message. Such behavior is ok on experimental stage, but Notifyd is production service now so not delivering notification is not an option.

**Why subscriptions are making it worse**

With the introduction of subscriptions this problem is getting more critical because the probability that more than 250 users will subscribe to certain event is growing. The amount of users that we have is still small and we're not yet impacted, that's why it's time to find a way to get rid of this limit.

**Problems with processing too many recipients at a time**

Needless to say we cannot just get rid of the limit, the limit is in place because of the performance reasons. Problems caused by too big collection of the recipients:

1. In-memory processing in Notify consumer: we manipulate the recipients collection as well as the list of subscriptions in memory. Both memory and time complexity of these manipulations are linear which means memory and time grow with the collection's size. That's why we can end up with unpredictable memory usage and processing times depending on the input and it will turn Notify consumer into bottleneck.
2. Heavy queries to MySQL that return large collection of results.
3. Authorization and policy checks in external services. External services that we use - authzd and monolith - also have to process the list of recipients we send to them and perform heavy database queries. Such load may affect availability of these services and also result in timeouts.

## Expected outcome

The goal is to remove recipients limit from Notifyd without turning Notify consumer into bottleneck.
This means processing times as well as memory usage shall be predictable and we shall be able to process incoming messages reliably without causing delays in notifications delivery.

## Goals and objectives

- Propose the solution and agree on it within the team
- Implement the solution that will result in expected outcome