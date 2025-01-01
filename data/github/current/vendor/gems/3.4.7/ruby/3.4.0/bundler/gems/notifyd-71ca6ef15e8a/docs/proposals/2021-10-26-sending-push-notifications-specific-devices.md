# [Proposal] Support sending push notifications to specific devices with Notifyd 

## Brief

[Support sending push notifications to specific devices with Notifyd ](https://github.com/github/notifyd/pull/465)

## Overview

We have outlined in the [brief](https://github.com/github/notifyd/pull/465) that we want to support the ability for integrators to send push notifications to specific devices only. It's required for 2-factor authentication use-case, because mobile devices need to have up-to-date version of mobile app that can handle 2FA authentication flow and go through 2FA setup flow that is described in the [issue](https://github.com/github/notifyd/issues/441).

Expected high-level flow to send notifications to specific devices:
![image](https://user-images.githubusercontent.com/5173831/139421153-b9e7fc2a-1c5e-4fbc-9d6d-45c4b81a340c.png)

### Solution exploration

We have considered several options to solving this problem:

#### 1. Add filtering criteria on Hydro message, that will specify devices that should receive push notification

With this approach we would give integrators a way to pass filtering criteria (`OAuthAccessIds`, `DevicePlatform`, `Service` or potentially `MobileDeviceTokens`) 
to specify devices which should get push notification on Hydro message that will be passed into notifyd pipeline.

For example in case of 2-factor auth we could think of such schema to pass `OAuthAccessIds` as filtering criterias:
```
{
 ... // rest of Hydro message
 Context: {
  PushNotificationsDevices: {
   Allowlist: {
    OAuthAccessIds: [`oauth_access_id_1`, `oauth_access_id_2`, `oauth_access_id_3`]
   }
  } 
 }   
}
```

🔼 schema above is quite generic and can be adapted for other use-cases.

From actual code perspective, relevant consumer can check if `PushNotificationsDevices` section is included on the Hydro message and based on data provided there select devices that will receive push notification.

In pseudo-code, it will look like:

```
    if msg.hasPushNotificationDevicesSkipCriteria() {
        // DO stuff to actually remove devices that are not on the list or not matching provided criteria
    }
```

We spiked into this approach in this PR https://github.com/github/notifyd/pull/470

For more context, service that powers 2-factor-authentication flow and initiates push notificaitons - `authnd`, stores mobile devices related information (device name and `OAuthAccessId`). `authnd` would be able to include `OAuthAccessId` as filtering criteria, when building Hydro message required by `Notifyd`.

**Benefits:**

- Notifyd would not bind to concrete integrator to get information about which devices should be skipped
- This interface is extensible, so we can reuse it for other use-cases or for negative filtering

**Drawbacks**

- This requires integrators to have data in hand that is supposed to be owned by us (biggest concern here is `MobileDeviceTokens` which is not used in current use-case)
- We push responsibility on integrators to push such filtering criteria, however building such hydro message will be more complicated
- Ultimately we need to push logic to filter devices somewhere and presumably it will leave in this new "system notifications" consumer, but would require us extra effort to port same device filtering logic to our "default" notifiations pipeline, while is fine because we don't have use-cases for that yet.
- There is also risk of introducing new pattern for filtering notifications in the delivery pipeline that partially deprecates the old one. 

#### 2. Take dependency on `authnd` to tell us which devices need to be skipped from getting push notification

This option is based off another [proposal](https://github.com/github/notifyd/blob/main/docs/proposals/enable-integrators-skip-default-checks-proposal.md), where we are talking about keeping notifyd pipeline as-is, but adding changes to skip checks in the monolith if notification reason matches `2fa`. 

In this case we may to consider having a hook for `authnd` in our delivery checks logic that we have on the monolith side. 

https://github.com/github/github/blob/master/app/api/internal/twirp/notifications/notifyd/v1/notifyd_api_handler.rb#L34-L55


```ruby
def check_deliver_mobile_push_policy(req, env)
    if req.reasons == ["2fa"] 
       
       # skip default checks 
       
       begin
        shouldDeliver = authNdClient.ShouldDeliverToDevice(user_id: req.user_id, oauth_access_id: req.oauth_access_id)  
        raise UndeliverableError.new("blocked 2fa device") unless shouldDeliver
       rescue StandartError
         raise UndeliverableError.new("failed 2fa device check")
       end

       return {
          is_deliverable: shouldDeliver
       }
    end

    raise UndeliverableError.new("blocked by settings") unless allowed_by_settings?(user, req.reasons)
    raise UndeliverableError.new("blocked by schedule") unless allowed_by_schedule?(user)
    
    # Rest of the checks

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

Such special check logic would rely on `reason` field that integrators already pass to us.

Here is a flow diagram how this could work:
![image](https://user-images.githubusercontent.com/5173831/139260113-e61971b8-f791-4677-a524-2cf942be32eb.png)

New checks are added in red color. `check_deliver_mobile_push_policy` will rely on `reason` field and if it matches `2fa`, we make call into `authnd` to tell us if notification should be delivered for such device.

This way we will make api call per recipient, per notification to make such checks (which is fine in 2FA use-case, because we always have single recipient). 
Using this pattern brings some trade-offs, however after discussing it with the team we are considering using [Notifyd_twirp_api handler](https://github.com/github/github/blob/master/app/api/internal/twirp/notifications/notifyd/v1/notifyd_api_handler.rb) as place where integrators can hook in additional filtering logic. 

**Benefits:**
- Extending existing pattern
- Not extending schema interface, which currently outweights drawbacks

**Drawbacks**
- We are adding another integrator specific check into our notifications filtering pipeline
- New call into `authnd` is yet another point of failure for such critical notification - e.g notifyd calls into `monolith`, which would call into `authnd`.
- We are making a logical circle because `authnd` already knows which devices should get push notification at the time they send us Hydro message. In this case we would make an extra call to get very same information. 
- Authnd needs to add and support extra endpoint on Twirp API.

## Proposed solution

We think our preferred solution is option 2)

Reasoning:

- Option 2 has it's tradeoffs, but we don't want to endup supporting 2 different filtering patterns. 
- Option 2 is trivial to implement from Notifyd side and won't affect rest of the pipeline. 

We are not going with Option 1. Although it provides a way to filter devices with declarative config, it is not going to fit or replace existing notifications filtering patterns.

 Currently we want to have single pattern to filter out notifications in notifyd pipeline. 


## Milestones

1. [Sync with Auth team and define API interface for filtering out devices](https://github.com/github/notifyd/issues/476)
2. [Extend monolith with select devices check ](https://github.com/github/notifyd/issues/476) going to be done by authnd team
4. [Add o11y for skip devices logic](https://github.com/github/notifyd/issues/479)

## Assumptions

- 2FA service will be able to tell us which device is valid based on `OAuthAccessIds`
