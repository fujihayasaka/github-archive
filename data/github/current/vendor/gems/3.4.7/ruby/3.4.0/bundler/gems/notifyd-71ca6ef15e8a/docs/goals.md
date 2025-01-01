# Problems to solve and goals

## Why does notifyd exist?
Notifyd is the result of a 2020 business need: the need to invest in the architecture of the Notifications
 Platform in order to support the use cases required by our pillar products. [This deck](https://docs.google.com/presentation/d/1SA5A4rq05-_4MGD_ew12nxklc8xUeT6cwntfUqZf1l4/edit#slide=id.gacb1cae55d_0_1) is a great read to better
  understand how we ended up creating notifyd and why now.

## What are the consumers we are trying to serve
The notifications AoR has always been an interesting hybrid. On one hand, we enable developers to be able to
 build new notification types on top of our platform. On the other hand, we provide and own user facing functionality
 . That is why it's important to explicitly list our consumers:

* **Github users**: will benefit from new features, and of course, from a fast and reliable experience. This includes
 dotcom and GHEx users.
* **Integrators**: they build new notification types on top of our platform.
* **Notification platform developers**: the notifications team and more widely the P&T group (for incident response
). They build and run the notifications platform.
* **Support engineers**: they troubleshoot issues that come up with notifications.

## Problems we are solving and goals to achieve

### Problem 1. Integrating with the notifications service is slow and risky

* **Goal 1**. Reduce the time it takes to add notifications support to a new product from 3+ weeks to 1 week tops
* **Goal 2**. Reduce to 0 the number of incidents caused in production due to integrators adding new notification

### Problem 2. Legacy thread + subscription model isn’t flexible enough
We want to make it possible to support more advanced notification functionality in a way that doesn’t require
 modifying core service code and doesn’t generate a terrible user experience.

* **Goal 1**. Support for more granular subscriptions
* **Goal 2**. Support for more channels
* **Goal 3**. Non subscription notifications support
* **Goal 4**. Reminders
* **Goal 5**. Relevant overview of notifications

*[Comprehensive list of integration requests and new features requests](https://github.com/orgs/github/projects/2526)

### Problem 3. Running the current platform is challenging from an operational perspective due to its rigidity
* **Goal 1**. The current platform treats all notifications equally, so we cannot process high priority notifications
 separate from others. We want to be able to manipulate notifications separately depending on their priority at the platform level
* **Goal 2**. We want to be able to gracefully handle a backed up queue of notifications
* **Goal 3**. As an integrator I want to be able to throttle notifications, rate limit, and monitor out of the box
* **Goal 4**. As a support engineer I want to be able to troubleshoot customer issues in an easy way
