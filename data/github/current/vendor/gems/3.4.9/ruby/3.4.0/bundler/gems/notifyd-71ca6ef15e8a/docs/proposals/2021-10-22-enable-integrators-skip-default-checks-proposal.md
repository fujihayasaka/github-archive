# [Proposal] Enable integrators to skip default checks in Notifyd notification pipeline

## Brief

[Enable integrators to skip default checks in Notifyd notification pipeline](../briefs/enable-integrators-skip-default-checks.md)

## Overview

As outlined in [Enable integrators to skip default checks](../briefs/enable-integrators-skip-default-checks.md) we would like support the ability for integrators to skip the default delivery checks i.e. is the user the actor, is the user spammy, does the user want to receive this notification etc. One thing that is assumed in this document is that _we (notifyd)_ still want to enforce that we make an authzd check in the delivery pipeline as we don't want to allow integrators to send pushes without _some_ form of check, no matter how naive it is.

Expected outcome:

![image](https://user-images.githubusercontent.com/5173831/138440790-94aa4d22-4a70-4041-b84b-8d0ee3359712.png)

### Solution exploration

The team considered multiple options to solving this problem:

#### 1. A special flag on the `notifyd.v0.Notify` and `notifyd.v0.DeliverMobilePush` hydro messages

With this approach we would support a “special casing” flag that would inform notifyd that the integrator wishes to skip the default checks via conditionals. Namely, we would do something like the following:

```
    if !msg.skipChecks {
        consumer.policyChecker.BatchCheckNotifyPolicy(...)
    }
```

So instead of:

![Untitled-2021-10-18-1139-5](https://user-images.githubusercontent.com/1643158/138478767-d35b8e8b-54a6-4fff-b2ad-1333fb8fed32.png)

It would look like this:

![Untitled-2021-10-18-1139-8](https://user-images.githubusercontent.com/1643158/138480651-386a35b1-d048-4439-8f5f-022682e62bee.png)

**Benefits:**

- This allows the integrator to add a simple field to the existing hydro event and achieve the result they need
- Integrators leverage the same pipeline

**Drawbacks**

- This approach is suboptimal as it would require us to litter the notifyd consumer with these checks, making the codebase more complex than it needs to be.

#### 2. Leverage the existing notifyd infrastructure

If we look at the checks that we want to remove, we have the following in the notify consumer:

- Notification actor is not a spammy user
- Recipient user is not suspended
- Recipient user is not a bot
- Recipient user is not an organization
- Recipient user is not ignoring the repository
- Author user is not blocked by recipient user

And the following in the deliver mobile push consumer:

- User is allowing to receive notifications by notification type (settings)
- User is allowing to receive notifications by schedule
- User is not blocked by saml restrictions

One option to achieve the desired result is do the following. 

- The `actor` field is [optional](https://github.com/github/github/blob/a4c1437d78d174ebb2836975c19d5da578e18811/app/api/internal/twirp/notifications/notifyd/v1/notifyd_api_handler.rb#L91-L96), if the integrator did not pass the `actor` into the message these checks will be skipped
- The `repoistory` field is also [optional](https://github.com/github/github/blob/a4c1437d78d174ebb2836975c19d5da578e18811/app/api/internal/twirp/notifications/notifyd/v1/notifyd_api_handler.rb#L138-L149), if the integrator did not pass the `repository` into the message, these checks will be skipped.
- We conditionally check if the user is suspended in the `batch_check_notify_policy` method based on the reason

So something like this:

```diff
+SKIP_CHECKS_REASON = ["2fa"].freeze

def batch_check_notify_policy(req, env)
    ...
+    if (req.reasons & SKIP_CHECKS_REASON).empty?
+        recipients = User.where(id: user_ids)
+        suspended_users_ids = recipients.suspended.pluck(:id)
+        suspended_users_ids.each do |user_id|
+            responses_by_user_id[user_id] = { user_id: user_id, notify: false, error: "user is suspended" }
+        end
+
+
+        not_suspended_ids = user_ids - suspended_users_ids
+        not_suspended_ids.each do |user_id|
+            responses_by_user_id[user_id] = { user_id: user_id, notify: true }
+        end
+    end
-    recipients = User.where(id: user_ids)
-    suspended_users_ids = recipients.suspended.pluck(:id)
-    suspended_users_ids.each do |user_id|
-       responses_by_user_id[user_id] = { user_id: user_id, notify: false, error: "user is suspended" }
-    end
-
-
-    not_suspended_ids = user_ids - suspended_users_ids
-    not_suspended_ids.each do |user_id|
-       responses_by_user_id[user_id] = { user_id: user_id, notify: true }
-    end
    ...
```

By doing this, it will enable the integrator to move through the `notify` consumer without performing the necessary checks but imporatantly, keeping the `authzd` checks. Then, the message moves into the `deliver-mobile-push-consumer`. Here what we could do is conditionally check if the reason is of the type that would like to skip the checks outlined above in the monolith twirp API. If `true` we would simply return `true` without performing the checks on [this](https://github.com/github/github/blob/a4c1437d78d174ebb2836975c19d5da578e18811/app/api/internal/twirp/notifications/notifyd/v1/notifyd_api_handler.rb#L36) line.

So something like this:

```diff
def check_deliver_mobile_push_policy(req, env)
    user = require_user(req)
+  
+   return true unless (req.reasons & SKIP_CHECKS_REASON).empty?
    raise UndeliverableError.new("blocked by settings") unless allowed_by_settings?(user, req.reasons)
    raise UndeliverableError.new("blocked by schedule") unless allowed_by_schedule?(user)

    unless req.skip_saml_enforcement
    org = require_organization(req)

    raise UndeliverableError.new("blocked by saml restrictions") unless allowed_by_saml_restrictions?(user, org, req.oauth_access_id)
    end

    {
        is_deliverable: true
    }

rescue UndeliverableError => e
    return {
    is_deliverable: false,
    error: e.message
    }
end
```

I think the argument against this is that now, we are requiring integrators to add conditional logic inside of notifyd. However, integrators already touch this file and perform a switch statement on the reason [here](https://github.com/github/github/blob/a4c1437d78d174ebb2836975c19d5da578e18811/app/api/internal/twirp/notifications/notifyd/v1/notifyd_api_handler.rb#L186-L200). So I question how much additional overhead this is introducing. Additionally this scopes the changes to this single file. So unlike option 1, we are not scattering logic around the codebase like we do in newsies. It's scoped to this specific file.

Here is a flow diagram of how I see this working:

![Untitled-2021-10-18-1139-15](https://user-images.githubusercontent.com/1643158/138927220-355d51f3-7fd3-4d14-817e-636407e450ad.png)

**Benefits:**

- It makes use of the existing notifyd pipeline and requires little to no changes in notifyd
- It keeps integrator changes scoped to a single file
- Does not require us to expand the scope of the interface of the notify hydro event
- There is already an ask to support notify messages without actor ids (https://github.com/github/notifyd/issues/296) 

**Drawbacks**

- We are bringing further integrator logic into notifyd
- These checks are becoming more implicit rather than explicit due to the data that you pass in to the message. I think we could tackle this via good documentation of these fields, but it would make it more ambiguous.
- At the moment the skipped fields in the notify consumer are only used for checks so can easily be skipped, what happens if we need to require these in the future?

#### 3. Make the `deliver-mobile-push-consumer` consumer publicly available

At the moment the `deliver-mobile-push-consumer` consumer is a "private" consumer. Namely, currently only the `notify` consumer emits events which are consumed by the deliver mobile push consumer. One approach that we explored was to expose this consumer publicly to the rest of GitHub. This would mean that other services were able to emit events which the `deliver-mobile-push-consumer` consumes.

So instead of:

![Untitled-2021-10-18-1139-5](https://user-images.githubusercontent.com/1643158/138478767-d35b8e8b-54a6-4fff-b2ad-1333fb8fed32.png)

It would look like this:

![Untitled-2021-10-18-1139-10](https://user-images.githubusercontent.com/1643158/138487971-43e601bb-2412-4834-9161-1d9aa68ee929.png)

**Benefits:**

- This means that instead of events traveling through the whole notifyd pipeline and putting conditionals everywhere we can scope these to purely the `deliver-mobile-push-consumer` consumer

**Drawbacks:**

- We have to expose an internal consumer to integrators. From a high level this seems OK but once it is done, we will need to support this.
- Although reduced in scope, we will still need to add conditionals to the `deliver-mobile-push-consumer` consumer as it contains the specific checks for the user such as schedules.
- It would require us to move the authzd checks into the `deliver-mobile-push-consumer` consumer.

#### 4. Custom rules engine

One route we explored is proving an interface to allow integrators to define _which_ checks they want to perform during the pipeline. The problem stated in the brief was to skip _all_ default checks, but allowing the user to define which checks to skip is more extensible and scalable.

As a rough example, this could look something like this (pseduo code):

```
    {
        skip_checks: ["schedules", "settings", "suspended"] <---
        explicit_recipients: [...],
        rendering: {...}
        notification_id: "...",
        authorization: {...},
        actor: {...},
        context: {...},
        tracking: {...}
    }
```

So instead of:

![Untitled-2021-10-18-1139-12](https://user-images.githubusercontent.com/1643158/138492486-9a6b07d2-0af5-4c87-b6fa-73a5cc856bbc.png)

It would look like this:

![Untitled-2021-10-18-1139-13](https://user-images.githubusercontent.com/1643158/138491279-cb41b21a-992b-4795-ac77-d3af6a7fd125.png)

**Benefits:**

- This is more extensible and scalable to other use cases where they may want to skip certain checks but not all.
- It allows the integrator to control what is skipped.
- It doesn't require changes in notifyd when the integrator wants to skip checks.

**Drawbacks:**

- The checks we have in notifyd right now are spread across multiple places. We have checks that call authzd, we also have two API end points which call the monolith. One in the `notify` consumer and one in the `deliver-mobile-push-consumer`. Each of these API calls check multiple things in one request. This would make it difficult to implement this solution without major refactoring.
- What happens when we add a new check? Do we enable it by default? Do we wait for integrators to update their messages?

#### 5. Setting up "system" notifications consumer

The final route we explored was to leverage a new consumer. I am calling it a "system" consumer but this is stil TBD (naming is hard.) Namely, we would require integrators to emit a different hydro message which is consumed by a new notifications consumer which skips the default checks.

So instead of the flow looking like this:

![Untitled-2021-10-18-1139-5](https://user-images.githubusercontent.com/1643158/138486354-6de8c2bc-c3df-476e-b79c-264b004bde94.png)

It would look like this:

![Untitled-2021-10-18-1139-11](https://user-images.githubusercontent.com/1643158/138488725-24de990d-7d40-4b5c-921f-a93af389e533.png)

**Benefits:**

- It allows us to separate this specific use case from the rest of the pipeline. One way to look at this is that this is a new "channel" a channel which eventually delivers mobile push notifications. But from a high level the channel is mutually exclusive from the existing channels as it does not perform default checks.
- Allows a clean separation of concerns

**Drawbacks:**

- We will have a new consumer to manage and deploy.
- It will require a new hydro schema to be created which will have a lot of duplicate info with the existing schema. Additionally we will need to expand the integrators interface and docs accordingly.
- We will need to manage the consumers security patches https://github.com/github/notifyd/issues/384
- We will need o11y + SLO's for this consumer

## Proposed solution

I think our long term strategy should be option 3 (_Custom rules engine_) as this enables more use cases and is more scalable. However, on evaluation this feels difficult to achieve with our current architecture without introducing significant technical debt or spending a lot of time refactoring. Additionally we are unsure if we are even going to get to this point as we have some hard dependencies on services that we can't allow integrators to skip such as org email requirements.

**We are proposing that we move forward with option 2 _Leverage the existing notifyd infrastructure_.**

Reasoning:

- It is a surgical move that requires no changes to the notifyd codebase
- The integrators need to make changes in these files any way, so having this single place to make changes feels right.

Tradeoff:

- We are making the condition of when to run these checks or not implicit based on whether fields are passed in or not
- Integrators are required to make changes in the monolith API handler to make reason specific checks.
