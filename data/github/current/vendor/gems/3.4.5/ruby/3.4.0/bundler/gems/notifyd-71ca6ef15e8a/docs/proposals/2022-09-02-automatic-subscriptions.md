# Proposal for automatic subscriptions during migration.

## Background

The [initiative][1] to migrate subscriptions from Newsies to notifyd brought [some questions][2] about what to do with thread auto-subscriptions.
These questions are of three different types:
- Product point of view: do existing auto-subscription behave as we believe they should?
- Ownership point of view: who should be the owner of auto-subscription data?
- Technical point of view: how can we solve auto-subscriptions in a viable way that minimizes the migration and maintenance work?

This proposal is focused on the last point and tries to describe the technical trade-offs of the different possible approaches.
It may also help with the first two points, which are not yet completely solved at the time of writing this proposal.

It may be useful to read [how thread auto-subscriptions currently work][3] to get more familiar with the problem at hand.

## Types of auto-subscribers

@mariorod gives some ideas about how auto-subscriptions should behave in his [thoughts on thread subscriptions][2].
In this section, we'll enumerate the currently existing types of auto-subscriptions and elaborate a bit on how they relate to those thoughs.

### Author

Thread authors are currently present in all thread types with auto-subcriptions and they behave consistently.
They should be notified when there's activity in the thread they have created.

### Comments

Thread commenters are currently present in all thread types with auto-subscritions and they behave consistently.
They should be notified when there's activity in the thread they have created.

### Mentions

Individual mentions in thread are currently present in all thread types with auto-subscriptions and they behave consistently.
Obtaining mentions usually requires parsing content currently, which is expensive in terms of performance.
Issues are exception to this behaviour, as _in some cases_ they have mentions _cached_ through issue events.

The notification behaviour for mentionees has important technical consequences and it should be defined before deciding on a technical approach.
There are two ways in mentions may behave:
- Mentionees become thread participants and they should be notified of any subsequent thread activity.
  This is the current behavior.
- Mentionees should be notified when they are mentioned in the thread but not in subsequent thread activity.
  In this case, mentions are stateless.

Note that while mentions may be expensive to process, their volume (number of people notified due to mentions) is relatively low.

### Team mentions

Team mentions in thread are currently present in all thread types with auto-subscriptions.
They mostly behave consistently except for issues, where auto-subscriptions are sometimes created through issue events with reason `subscribed`.
Obtaining team mentions usually requires parsing content currently, which is expensive in terms of performance.
Issues are exception to this behaviour, as _in some cases_ they have mentions _cached_ through issue events.

The notification behaviour for team mentionees has important technical consequences and it should be defined before deciding on a technical approach.
There are two ways in mentions may behave:
- Team mentionees become thread participants and they should be notified of any subsequent thread activity.
  This is the current behavior.
- Team mentionees should be notified when they are mentioned in the thread but not in subsequent thread activity.
  In this case, team mentions are stateless.

Apart from the processing costs of team mentions, their volume (number of people notified due to team mentions) is also problematic.
See https://github.com/github/notifications/issues/1430 for some further context.

### Assigns

Assigns are only available for Issues and they are handled by Issue Events.
The assignee is a user.
They should be notified when there's activity in the thread they have created.

### Review requests

Review requests are only available for Issues (Pull Requests) and they are handled by Issue Events.
The _requestee_ may be an user or a team.
They should be notified when there's activity in the thread they have created.

As the requestee may be a team, the volume of notifications (number of people notified due to review requested activity) may be problematic.

### State changes

These three types are Issue thread type specific and they are all handled through issue events.
There's a large number of issue events of this type, and currently the event actors are subscribed to the thread.
It's unclear if this makes sense from the product point of view, probably many of these types shouldn't create a subscription.

## Potential solutions

In this section, we explore the different potential solutions available and discuss their trade-offs and ownership implications.

### Migrate the existing auto-subscriptions behavior

A possible solution is to maintain the current behavior and migrate everything as it is.

Pros:
- Reduce the migration risk as product changes are decoupled from migration.
- Easier to validate migration success.

Cons:
- Delays any solution to the product or ownership challenges.
- Higher volume of subscriptions to be handled in notifyd, which may increase scalability requirements (sharding, etc.)
- May infer in some _wasted_ effort if we need to immediately change the behavior after migration.

### Move auto-subscriptions to an independent service

Similar to the previous approach, we keep the existing behavior and migrate everything as it is, but we migrate auto-subscriptions to its own service,
independent of the rest of the notifyd platform subscriptions / routing settings.

Pros:
- Reduce the migration risk as product changes are decoupled from migration.
- Easier to validate migration success.
- Auto-subscriptions are isolated from the rest of the platform which may make moving them out of notifications easier in the future.
- Splitting the data may reduce / isolate some scalability problems.
- Opportunity to build a better participation graph for users in a future iteration.

Cons:
- Delays any solution to the product or ownership challenges.
- May infer in some _wasted_ effort if we need to immediately change the behavior after migration.
- It requires creating, maintaining and operating a new service.
- It makes notification logic more complex as it requires to hit an additional service.

### Rethink auto-subscriptions before migrating

Similar to the previous (two) approach(es), but we rethink auto-subscriptions before migrating them,
which may result in a simplified migration (e.g. drop team mentions, some state changes, and keep the rest).

Pros:
- Possible to give solution to some of the existing product problems faster.
- Reduced amount of migrated data may reduce scalability problems.

Cons:
- Increased migration risk as a new dependency / refactoring is added, and bigger integrator involvement may be required.
- Harder to validate migration success as the output is no longer comparable.

### Move all thread activity to an independent service

We want to build a consistent notification model across thread types.
A way to achieve this it to centralize all thread activity in a single service that then can be reused among different integrators.
There already exists [a proposal][4] for such a service.

Pros:
- Best integrator experience.
- Best ownership approach, thread activity is moved out of notifications ownership.
- Easier to scale and optimize as there's a single point to do so.
- Easier to keep a consistent behavior.

Cons:
- A new dependency for the migration initiative that poses a **huge** risk,
  as it requires the new service to be developed and integrated by every integrator.
- Request size may become big, with people to notify in the order of 10k.

### Leave auto-subscription handling to integrators

The work of recreating auto-subscribers is left to integrators.
The notifications team may still facilitate a consistent behavior through a good API and even provide the initial implementation,
but the ownership is left to integrators.

Pros:
- Thread activity / participants ownership out of notifications.
- No auto-subscription state.
- No auto-subscription migration.
- Lower subscription volume / less scalability problems.

Cons:
- Increased complexity on the integrator's side.
- Regenerating auto-subscribers as explict recipients may be more expensive.
- It may require caching mechanisms that each integrator must solve.
- More integrator involvement.
- Notification events may become big with explicit recipients people in the order of 10k.

### An hybrid approach

More than a solution, this is just a reminder that we are not required to provide the same solution for every thread type.
Not doing so will worsen the consistency problem, but it may also simplify the migration and put us in a position to explore better directions faster.

## Data analysis

We have gathered some data to help us drive the discussion of the solution approach.
The data is imperfect (data restricted to 30 days, some tables are missing, etc.), but it should be good enough for decision making.
We have tried to retrieve actual notification data where possible.

The data analysis is split by each of the subjects with auto-subscriptions as described in [this document][3].
For each subject we have tried to answer the following questions:
- What's the notification rate, that is, the rate of activity that trigger a notification event, per subject.
- For each notification, what's the volume of auto-subscribers? Or similarly, if we drop auto-subscriptions, how would the volume of explicit recipients increase?
- For each notification, what's the cost / complexity of regenerating these explicit recipients?

### RepositoryAdvisory

Repository advisories have 3 types of auto-subscriptions:
- `comment`, one per repository advisory comment
- `mention`, unbounded, as the advisory and each comment can have an arbitrary number of mentions.
- `team_mention`, unbounded, as the advisory and each comment can have an arbitrary number of mentions.

We had [847 in 30 days][5].
Regenerating comments for each notification would be cheap.

Unfortunately, we don't seem to have data for repository advisory comments available in data-dot.
I have just looked into the db data and we can see that the number of comments is in the same order of magnitude as advisories themselves:
```
console_ro2 07:21:05 collab-slow: github_production> SELECT COUNT(*) FROM repository_advisories;
+----------+
| COUNT(*) |
+----------+
|    13963 |
+----------+
1 row in set (0.00 sec)

console_ro2 07:21:34 collab-slow: github_production> SELECT COUNT(*) FROM repository_advisory_comments;
+----------+
| COUNT(*) |
+----------+
|    74542 |
+----------+
1 row in set (0.03 sec)
```
We can infer from this data that regenerating mentions would also be cheap.

The volume of [explicit recipients due to auto-subscribers][6] would increase on at most 14, which is negligible.

### Gists

Gists have 3 types of auto-subscriptions:
- `author`, one per gist.
- `comment`, one per gist comment.
- `mention`, unbounded, as each comment can have an arbitrary number of mentions

We had [16676 unique notification events in 30 days][7], ~500 events per day.
Regenerating authors and comments for each notification would be cheap.

In the same time period we had [1927202 gist comments involved in these notifications][8],
which on average it'd require 44 comment parsing per minute to extract all the mentions,
but we can have a single notification requiring parsing as many as 7867 comments.
Regenerating mentions in this way would be feasible but not cheap.

The volume of [explicit recipients due to auto-subscribers][6] would increase on ~45 subscribers on average, with an upper-bound of < 500.
[Mentions aren't a big factor here][9], this increase in volume wouldn't be significantly altered by moving to a stateless mention approach.

### Discussion

Discussions have 4 types of auto-subscriptions:
- `author`, one per discussion.
- `comment`, one per discussion comment.
- `mention`, unbounded, each discussion and each discussion comment can have an arbitrary number of mentions.
- `team_mention`, unbounded, each discussion and each discussion comment can have an arbitrary number of team mentions.

There are also some auto-subscriptions in discussions that are obsolete and come from converting issues to discussion.
The most reasonable approach seems to just don't regenerate subscribers for these, as they don't make sense anymore.
These obsolete auto-subscription reasons are: `milestone`, `subscribed`, `state_change` and `assign`.

We had [254356 unique notification events in 30 days][10], ~5 events per minute.
Regenerating authors and comments for each notification would be cheap.

In the same time period we had [5562698 discussion comments involved in these notifications][11],
which on average it'd require parsing close to 2 comment per second to extract all the mentions,
but we can have a single notification requiring parsing as many as 5260 comments.
Regenerating mentions in this way may be feasible but expensive.

The volume of [explicit recipients due to auto-subscribers][6] would increase on ~6 subscribers on average, with an upper-bound of 3748.
[Mentions aren't a big factor here][9], this increase in volume wouldn't be significantly altered by moving to a stateless mention approach.
Team mentions seem to be relevant for the upper-bound of recipients due to auto-subscriptions.

### Commits

Commits have 4 types of auto-subscriptions:
- `author`, at most one per commit comment
- `comment`, one per commit comment
- `mention`, unbounded, each commit and each commit comment can have an arbitrary number of mentions.
- `team_mention`, unbounded, each commit and each commit comment can have an arbitrary number of team mentions.

We had [2399406 unique notification events][12] in 30 days, ~1 event per second.
Regenerating authors and comments for each notification should be feasible.

In the same time period we had [7268885063 commit comments involved in these notifications][13],
which on average it'd require parsing close to 3k comment per second to extract all the mentions,
but we can have a single notification requiring parsing as many as 160807 comments.
Regenerating mentions in this way is **not** feasible.

The volume of [explicit recipients due to auto-subscribers][6] would increase on ~4 subscribers on average, with an upper-bound of 3745.
[Mentions aren't a big factor here][9], this increase in volume wouldn't be significantly altered by moving to a stateless mention approach.

### Issues

Issues have the following types of auto-subscriptions:
- `author`, one per issue.
- `comment`, one per issue comment / one per pull request review comment.
- `assign`, one per assigned issue event.
- `review_requested`, an unbound number per review requested event, as it may generate one (users reviewer) or many (team reviewer).
- `mention`, unbounded, each issue, issue comment and review request comment may have an arbitrary number of mentions.
- `team_mention`, unbounded, each issue, issue comment and review request comment may have an arbitrary number of mentions.
- `state_change`, one per issue event that doesn't have any other reason.
- `security_alert`, obsolete.

We had [157173465 unique notification events][14] in 30 days, ~60req/s.
At this rate, any kind of content parsing to regenerate mentions is no longer feasible.
Regenerating the rest of current auto-subscribers also present some challenges, compared to how auto-subscribers currently work
(simplifying, just a single db query to retrieve all the users subscribed to the particular thread):
- It requires queries to multiple tables: `issues`, `issue_comments`, `issue_events`, `issue_event_details`, `pull_request_review`, `pull_request_review_comments`, etc.
  Some may be avoidable in some cases (depending whether the issue is a PR or not), but still a handful of them.
- Issue events have a polymorphic `Subject` field, which may be a `Team`, requiring an additional query/queries to retrieve all the team members.
  [These cases][15] should be relatively rare, but non-negligible.
- Auto-subscriptions in Issues have a pretty complex logic, and replacing them means making significant business logic changes.
  This brings some risks, and also the opportunity to rethink and simplify the notification approach for Issues.

The volume of [explicit recipients due to auto-subscribers][6] would increase on ~6 subscribers on average, with an upper-bound of 4520.
[Mentions aren't a big factor here][9], this increase in volume wouldn't be significantly altered by moving to a stateless mention approach.
Team mentions seem to be relevant for the upper-bound of recipients due to auto-subscriptions.

## Proposal

As the previous analysis, a key question should be answered before making a final decision: are mentions and team mentions stateful or stateless?
Let's explore both cases.

### Mentions and team mentions are stateless.

In this case, the following approach is proposed:

- Leave auto-subscription handling to integrators for all thread types, except Issues.
- Move Issue notifications to an independent service, owned by the notifications team.

The notification rate and cost and complexity of regenerating the auto-subscribers as explicit recipients is manageable for most thread types.
This means migrating auto-subscriptions for most integrators is not really needed and the ownership can be moved to integrators faster.
We can also enable some further exploration faster with these integrators, towards product changes or a new service that takes care of all thread activity.

Issue notifications, on the other hand, have a high rate, cost and complexity and dealing with them now will put at risk the migration initiative.
We may want to simplify or remove some of these auto-subscribers types, but it'd be safer to decouple this from the migration initiative.
Any deeper / further iterations on issues participants should be addressed later / independently but should move in the same direction as with the rest of thread types,
towards moving auto-subscriptions out of the notifications ownership and into the integrators.

### Mentions and team mentions are stateful

In this case, the following approach is proposed:

- Move auto-subscriptions to an independent service.

Stateful mentions and team mentions are expensive enough for any thread type
(except `RepositoryAdvisory`, but it's not worth the effort of making an exception for it),
that it'd require some non-trivial caching mechanism.

In this scenario, leaving the responsibility of handling this work to each integrator doesn't seem a valid approach,
a much better aprpoach would be to go with an independent service that handles all the thread activity.
Unfortunately, this will require a non-trivial amount of time to be developed and integrated,
and it'd put the migration initiative in a huge risk.

As a compromise solution, all the existing auto-subscriptions can be moved to a new service, isolated from the notifications platform,
so that this activity handling can then be moved to such an external service.

[1]: https://github.com/github/planning-tracking/issues/1127
[2]: https://gist.github.com/mariorod/f90478023102bd9be6cd0d9cb86ba9b8
[3]: https://github.com/github/notifications/blob/master/docs/how-dotcom-autosubscriptions-work.md
[4]: https://docs.google.com/document/d/1yNf9voorjN1ba9w5l_AWz_9McHuNMZBnmnOPrhrd6s0/edit#heading=h.o6vfskp34xw5
[5]: https://data.githubapp.com/sql/share/1f63987f
[6]: https://data.githubapp.com/sql/share/228f047f
[7]: https://data.githubapp.com/sql/share/a07001d4
[8]: https://data.githubapp.com/sql/share/39c5cbf9
[9]: https://data.githubapp.com/sql/share/d6a4cdad
[10]: https://data.githubapp.com/sql/share/caff3db0
[11]: https://data.githubapp.com/sql/share/e8ebbf2d
[12]: https://data.githubapp.com/sql/share/6233f6af
[13]: https://data.githubapp.com/sql/share/9d689869
[14]: https://data.githubapp.com/sql/share/dc2753af
[15]: https://data.githubapp.com/sql/share/d3aa54a2
