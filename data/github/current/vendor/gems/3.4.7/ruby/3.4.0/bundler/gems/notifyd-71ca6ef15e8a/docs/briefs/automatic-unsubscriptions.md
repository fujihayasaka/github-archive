# Automatic unsubscription

## Problem statement
We want to unsubscribe users automatically when they or the system takes an action that should implicitly unsubscribe them. The situations include but are not limited to:
1. A repository is converted into a private repo and the user is not a member
1. A user is removed as a collaborator from a private repo
1. A user is removed as an org member from an org and that org has private repos (could be the same as above)
1. A user's account is deleted or permanently suspended
1. A label is deleted see [kitchen_sink.rb for more details](https://github.com/github/github/blob/f490e148d39c66361f5217d127b2729700bb487b/config/instrumentation/hydro/subscriptions/kitchen_sink.rb#L1880-L1888)

## Context
There is a myriad of ways users can be automatically unsubscribed from Newsies notifications. We need to ensure that notifyd subscriptions are also deleted for users in all of these cases. The risk of not automatically unsubscribing users is that notifyd will use resources to fetch users and then immediately remove them via a request to authzd. As the product grows and we begin to take on larger organizations, this "fetch and reject" cycle will have a noticeable impact on resources and performance. 

### How it works in Newsies 
Today Newsies removes users via two paths. 
1. Jobs that are triggered by specific events such as user loosing access to a repo
1. a clean up job that runs when the system [checks if a thread is readable for a user](https://github.com/github/github/blob/b538ae859c887b0d773d96a268f2399feb710c8c/lib/platform/models/notification_thread.rb#L35-L68)

#### Maintenance jobs ordered by most called in last 3 months
![image](https://user-images.githubusercontent.com/4596845/154082913-cc3dceee-db44-4823-b4b4-989f83ec7031.png)

#### Relevant jobs
As of 22-02-2022 notifyd only stores subscription information for labels. This type of subscription is most similarly related to `ThreadTypeSubscription` in the monolith. Below are the jobs that contain unsubscriptions for `ThreadTypeSubscription` and are valuable places to study when we design a solution.

```
Newsies::DeleteAllForListAndUsersJob - (list_type, list_id, user_ids)
Newsies::DeleteAllForListJob - (list_type, list_id)
Newsies::DeleteAllForUserAndListsJob - (user_id, list_hashes)
Newsies::DeleteAllForUserAndRepositoryOwnerJob - (user_id, owner_id, subscription_type)
Newsies::DeleteAllForUserJob - (user_id)
Newsies::DeleteForUserAndAllRepositoriesJob - (user_id, list_type, subscription_type)
Newsies::DeleteThreadTypeSubscriptionForListAndUsersJob - (list_type, list_id, user_ids, thread_type)
```

## Goals and objectives
* Gather data on authzd rejections to understand:
    * how the lack of automatic unsubscriptions affects performance
    * why authzd rejects users
* Design automatic unsubscriptions solution that accounts for
    * cases when github/github unsubscribes users automatically 
    * cases when automatic unsubscribes have failed and the system requires cleanup

## Assumptions
* The "fetch and reject" cycle will become a significant resource and performance issue in the future

## Guiding Principles
* We need a way of automatically deleting subscriptions that might work with multiple integrators
* We want to make sure that notifyd code remains as isolated as possible from Newsies
