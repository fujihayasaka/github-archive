# Import data to staging database for testing purposes

## Problem statement

We want to start using the staging environment for testing purposes. This could be a big benefit for us and for integrators. 

Even if we can use staging for testing, we need data in the staging database to start testing. The issue here is that the staging database is not synchronized with the production database. In a first approach, we will need to synchronize data for:
- Label subscriptions
- Device tokens

We don't want to sync the data periodically. The intention with these solutions is importing the data only for testing. Data imported to staging won't expire or be removed. Once imported, data will stay in staging db.

## Proposals

I propose three different solutions for this problem:
- Option 1: Insert data through CLI
- Option 2: Reuse `sync_device_tokens` job or create a new job to sync data from monolith
- Option 3: Create a section in devtools to import data

### 1. Insert data through CLI

The idea is to create a command to insert data to staging. I’ve spiked into a solution in here: https://github.com/github/notifyd/pull/938/files following a similar approach as [authzd does](https://github.com/github/authzd/blob/master/docs/authzd-development.md#performing-requests-via-cli).

**Is it valid for label subscriptions?** Yes, the spike PR is applied to label subscriptions, and it works by using the following commands. Let’s say I want to import label subscriptions for a specific `user_id` and `repository_id`:

```
> script/import-data subscriptions -u <user_id> -r <repository_id> -d <import_in_dev?> -s <hmac>
> script/import-data subscriptions -u 8514581 -r 197476416 -d false -s hmac
```

**Is it valid for device tokens?** To import device tokens for a user, we’d need something similar:

```
> script/import-data mobile-pushes -u <user_id> -t <device_token> -d <import_in_dev?> -s <hmac>
```

The problem here is to obtain the **device token** for a specific user. We have different options:
1. Return this value in data warehouse and get the value with a similar approach as authzd is doing for [`authzd-acl-load`](https://github.com/github/authzd-acl-load/tree/main/datagen), using the [presto-go-client](https://github.com/prestodb/presto-go-client/). The drawback of this is that we won't access to the most recent data, since snapshots are made every 24h.
2. Create an endpoint to return the `device_token` for a `user_id`.
3. Use a chatops command to return the `device_token` for a user id, similar to the `.uid @login` command that returns the id of a user, we can use something like `.notifyd device_token @login` to get the token for a user 

I propose to use the last option to obtain the `device_token` for this case, because of the benefits described below.

**How can we create a temporary hmac token?**: We can use the [same approach as `authzd`](https://github.com/github/authzd/blob/041eb4c71d39b2760d8f06611472f0fb4b7c082f/internal/chatops/chatops.go#L75): use chatops to create and return a temporary hmac token that expires in x minutes, using a command like `.notifyd hmac`

This is the final schema that represents the first option:
<img width="795" alt="Screenshot 2022-03-24 at 19 53 58" src="https://user-images.githubusercontent.com/8514581/159989871-283c5f08-9d89-4dfa-8451-1ad43925c982.png">

**Benefits:**
- It is easy to implement, since we are using the already existing endpoints
- It is easy to use and intuitive, so it is a benefit for integrators
- We are not creating extra endpoints
- We can reuse chatops for other commands 
- Logic is outside of the monolith
- Is a low-risk implementation, since it does not connect directly to database or exposes device tokens or other data in the api or data warehouse
- We can have an alternative way to import data: either using cli command or chatops
- We can use it to import data either to staging or local database

**Drawbacks**
- It could not be compatible with new code versions or implementations, so it will require maintenance.
- It [requires VPN](https://thehub.github.com/security/security-operations/developer-vpn-access/) access to execute the commands

#### 2. Reuse `sync_device_tokens` job or create a new job to sync data from monolith

In the past we created the [sync_device_tokens_job](https://github.com/github/github/blob/master/app/jobs/notifyd/sync_device_tokens_job.rb) to sync `device_tokens` between notifyd and the monolith using the `ReplaceDeviceTokens` endpoint from notifyd. We could proceed in a similar way: create a `sync_staging_data.job` for example, and add all the logic there to import data to staging database, using the existing endpoints for label subscriptions and device tokens.

An engineer will proceed by executing this job in review-lab to import the data needed to test in staging:

```
Notifyd::SyncStagingData(user_id: 1234).perform_now
```

**Benefits:**
- It is easy to implement, since we are using the already existing endpoints
- It is easy to use and intuitive, so it is a benefit for integrators
- We are not creating extra endpoints
- We have the device_token available in the monolith
- Is a low-risk implementation, since it does not connect directly to database or exposes device tokens or other data in the api or data warehouse

**Drawbacks**
- It will require maintenance if new implementations are added
- We are adding notifyd logic outside of notifyd, so it breaks the fundamental requirement of ["Separation from newsies"](https://github.com/github/notifyd/blob/main/docs/fundamental-requirements.md#2-separation-from-newsies)
- It is not compatible with the migration, since data could be removed from the monolith sooner or later.


#### 3. Create a section in devtools to import data

In the past we had a section in [devtools](https://admin.github.com/devtools) for notifyd actions that we removed in this PR: https://github.com/github/github/pull/187548 

We can create it again, and use it to call the logic to sync data. We will have a `/notifyd` route in devtools and buttons like: "Import subscriptions to staging"

**Benefits:**
- It is integrator-friendly, easy to use and intuitive
- We are not creating extra endpoints
- We have the device_token available in the monolith
- Is a low-risk implementation, since it does not connect directly to database or exposes device tokens or other data in the api or data warehouse
- It could  be used for future implementations

**Drawbacks**
- It will require maintenance if new implementations are added
- We are adding notifyd logic outside of notifyd, so it breaks the fundamental requirement of separation from newsies: https://github.com/github/notifyd/blob/main/docs/fundamental-requirements.md#2-separation-from-newsies
- It is not compatible with the migration, since data could be removed from the monolith sooner or later.
- It requires more time to develop, so it is necessary to create the logic + views

## Proposed solution

We are looking for a solution with these requirements:
- **Easy to implement**, since it is for a **first version of staging** that allows us to test. We don’t want all the production records in staging. This way we will realized about what is missing and what is not for staging.
- **Low-risk solution**: we don’t want to create new endpoints, change vault secrets or expose data just for testing purposes
- **Easy to maintain**: the solution should be compatible with new versions of the code as much as possible

So the proposed solution is: Solution 1 -> CLI + chatops to import data in staging. 
