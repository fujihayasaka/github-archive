# Support sending push notifications to specific devices with Notifyd

## Problem statement

Notifyd automatically sends push notifications to all devices associated with a recipient of a push notification. Integrators should be able to tell notifyd that a push notification should only be delivered to some specific devices.

Expected flow: 
![image](https://user-images.githubusercontent.com/5173831/139421153-b9e7fc2a-1c5e-4fbc-9d6d-45c4b81a340c.png)

## Context
Integrators want to manage which devices will get push notifications, for example in 2FA use-case only authorized devices can receive the notification.  

In the diagram below you can find full expected 2FA + notification flow with step by step explanation:
![image](https://user-images.githubusercontent.com/5173831/138491294-aa5afd2b-2c6b-4b03-9e93-ce9cdf030740.png)

1) During 2FA setup mobile device will generate private/public key pair
2) Mobile app will register public key to AuthNd, together with user `OAuthAccessId` that will be stored on `AuthNd` side.
4) `Notifyd` should send push notifications only to devices that are setup for 2FA. 

More details about how 2FA will authorize devices are documented [in this issue](https://github.com/github/notifyd/issues/441).

## Goals and objectives
By the end of this project we expect to have:

1. Integrators are able to specify which devices should receive push notification 

## Assumptions
- Integrators should send criteria to filter mobile devices that are supported by Notifyd. My assumption based on the requirements, is that this will work using the `mobile_device_token` or `oauth_access_id` fields stored in the `mobile_device_tokens` table in Notifyd. 

## Open questions

- 10% of `mobile_device_tokens` records have `oauth_access_id` set to `NULL`. Does it impact the solution? 

## Guiding Principles
* Notifyd should not include domain specific logic
