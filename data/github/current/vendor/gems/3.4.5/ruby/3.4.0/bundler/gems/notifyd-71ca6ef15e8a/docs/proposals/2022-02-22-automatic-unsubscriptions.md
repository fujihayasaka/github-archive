# TODO
- This proposal is currently serving as a place holder for potential solutions collected during the investigation in [issue #758](https://github.com/github/notifyd/issues/758). When the team decides to revisit this topic more solutions will be explored in detail. 

# [Proposal] Automatic unsubscription

## Brief

[Automatic unsubscription](../briefs/automatic-unsubscriptions.md)

## Overview

As outlined in the [brief](../briefs/automatic-unsubscriptions.md), we would like to unsubscribe users automatically when they or the system takes an action that should implicitly unsubscribe them.

## Considerations


## Solution exploration

## Potential solutions 

### Solution 1: Parallel Newsies Unsubscription Path

1. Create "sibling" jobs for each of the relevant newsies jobs 
`Newsies::DeleteAllForListAndUsersJob - (list_type, list_id, user_ids)` -> `Notifyd::DeleteAllForListAndUsersJob - (list_type, list_id, user_ids)`
1. Add the Notifyd "sibling" job as a sprout class into the Newsies job to be preformed later.
```ruby
  class DeleteAllForListAndUsersJob < MaintenanceBaseJob
    # list_type - String newsies list type
    # list_id   - Integer newsies list id
    # user_ids   - Array of Integer user ids
    def perform(list_type, list_id, user_ids)
      Notifyd::DeleteAllForListAndUsersJob.perform_later(list_type, list_id, user_ids)
```
1. Each of the "sibling" jobs will call the `Delete` Twirp endpoint. 
1. We will modify the Twirp `Delete` endpoint to accept different arguments and resolve the differences internally. For example, the following should be valid
```
Notifyd::Proto::DeleteRequest.new(user_id: id, topics: to_delete)
Notifyd::Proto::DeleteRequest.new({attributes: [{name: "repository_id", value: list_id}]})
Notifyd::Proto::DeleteRequest.new(user_id: id)
```

I considered other ways of adding similar logic without explicitly adding the Notifyd job into each Newsies job, but I felt it obfuscated the purpose too much. Also, I realize that we will have to get more data from NotifyD to do these deletions properly and that in some cases we will have to add endpoints. I think that should be decided on a case-by-case basis.  

#### Relevant jobs
Newsies::DeleteAllForListAndUsersJob - (list_type, list_id, user_ids)
Newsies::DeleteAllForListJob - (list_type, list_id)
Newsies::DeleteAllForUserAndListsJob - (user_id, list_hashes)
Newsies::DeleteAllForUserAndRepositoryOwnerJob - (user_id, owner_id, subscription_type)
Newsies::DeleteAllForUserJob - (user_id)
Newsies::DeleteForUserAndAllRepositoriesJob - (user_id, list_type, subscription_type)
Newsies::DeleteThreadTypeSubscriptionForListAndUsersJob - (list_type, list_id, user_ids, thread_type)


### Solution 1: On-the-fly Subscription Cleanup

These cases are more challenging because we want to make sure the system has a way of cleaning up subscriptions when automatic subscriptions fail. The existing system does this clean-up; however, it's unclear if this will be an issue for Notifyd. Adding a clean-up to the notification path also causes unexpected side effects for the integrator that might cause issues further down the line. 


## Proposed solution
We unsubscribe a user depending the reason authzd rejects a user.

**Reasoning**
