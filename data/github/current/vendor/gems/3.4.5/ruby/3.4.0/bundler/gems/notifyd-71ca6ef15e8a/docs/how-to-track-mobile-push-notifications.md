This is a guide to make finding notifications logs easier. These are the key questions:

- Has the notification reached `notifyd`?
- What keys: `notification_id`, `user_id`, `msg`, `error`... does `notifyd` provide?
- Has the notification been delivered?

# How to track mobile push notifications?

- [notifyd log data](#notifyd-log-data)
- [notifyd log journey](#notifyd-log-journey)
   - [1. Processing Notify message](#1-processing-notify-message)
   - [2. Delivering mobile push message](#2-delivering-mobile-push-message)
   - [3. Notification delivered](#3-notification-delivered)
- [Log examples](#Log-examples)

## notifyd log data

When checking a notifyd log in Splunk, the most important keys to focus on are:

- `user_id`: recipient id of the notification
- `notification_id `: notification id. This value is configured in the corresponding subject adapter. For example, for Issues and IssueComments is the permalink:
```
# Issues
/wantedly/post-mortems/issues/331

# IssueComments
/github/product-360/issues/324#issuecomment-941838260
```
- `msg`: Information about the notification status
- `gh_app`: application, this value should be `notifyd`
- `gh_env`: this value should be `production`

## notifyd log journey

The following messages are recorded in `msg` key:

### 1. Processing Notify message

In this first step, `notifyd` makes `authzd` checks and policy checks against the monolith, and a delivery could be skipped based on these reasons:

- `skipping notification delivery because recipient matches the actor`: The recipient  is the same as the actor.
- `skipping notification delivery for unauthorized recipient`: When checking `authzd`, the recipient is not authorized to receive a notification.
- `skipping notification delivery because not passed notify policy: <reason>`: When checking policy checks in the monolith.
- If any of the external requests fails: 
```
msg = notify consume error
level = ERROR
```
- `notifications published`: If this step went well.

### 2. Delivering mobile push message

In this second step, `notifyd` fetch the user device tokens and makes mobile push policy checks against the monolith, and a delivery could be skipped based on these reasons:

- `processing DeliverMobilePush message`: means this process has started
- `no device tokens`: When user does not have device tokens, the delivery is skipped.
- `skipping notification delivery because not passed mobile push policy: <reason>`: When checking mobile push policy checks in the monolith. This check is per device token.
- `no valid device tokens after checking mobile push policy`: After checking mobile push policy, delivery is skipped if no device token is valid. This check is per user.
- `skipping notification delivery because is duplicated`: When the notification has already been sent.
- `couldn't build notification`: When there is an issue with the layout
- If the external request fails:
```
msg = couldn't check policy
level = ERROR
```
- If there is an issue related with the database: `error fetching device tokens`, `error fetching deliveries`.

### 3. Notification delivered

- `notification delivered`: When a notification has been delivered with success. 🚀

## Log examples

#### Success example log

[Example](https://splunk.githubapp.com/en-US/app/gh_reference_app/search?q=search%20index%3Dnotifyd%20gh_env%3Dproduction%20gh_app%3Dnotifyd%20msg%3D%22notification%20delivered%22&display.page.search.mode=smart&dispatch.sample_ratio=1&earliest=-60m%40m&latest=now&sid=1634115621.8620_5FB4AC8E-DC1F-4236-99DC-C6032DC30760)

<img width="600" alt="Screenshot 2021-10-13 at 11 20 27" src="https://user-images.githubusercontent.com/8514581/137106722-e3e1ba92-fb6c-438b-ac25-860ae17c76e3.png">

#### Skipped notification example log

[Examples](https://splunk.githubapp.com/en-US/app/gh_reference_app/search?q=search%20index%3Dnotifyd%20%22skipping%20notification%20delivery%20because%20not%20passed%20mobile%20push%20policy*%22%20notifyd&display.page.search.mode=smart&dispatch.sample_ratio=1&earliest=-60m%40m&latest=now&sid=1634117938.8942_5FB4AC8E-DC1F-4236-99DC-C6032DC30760)

<img width="600" alt="Screenshot 2021-10-13 at 11 27 07" src="https://user-images.githubusercontent.com/8514581/137106711-c3149e9e-df1c-45f5-8203-e57c4df40289.png">

#### Error log example

[Examples](https://splunk.githubapp.com/en-GB/app/gh_reference_app/search?q=search%20index%3Dnotifyd%20level%3D%22ERROR%22%20gh_app%3Dnotifyd%20gh_env%3Dproduction&display.page.search.mode=verbose&dispatch.sample_ratio=1&earliest=1633526358.153&latest=1633526358.154&sid=1634117970.8943_5FB4AC8E-DC1F-4236-99DC-C6032DC30760)

<img width="600" alt="Screenshot 2021-10-13 at 11 28 12" src="https://user-images.githubusercontent.com/8514581/137106701-3c2f781f-7c23-4882-96a3-8bfd5cd5b6d9.png">
