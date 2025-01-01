# Enable integrators to skip default checks in Notifyd notification pipeline.

## Problem statement

We want to support a new push notification type - push notifications for 2-factor authentication (we will refer to this as 2FA). 

Our current notification pipeline doesn't support this use-case, because our pipeline currently has default checks built-in. Push notifications like [2FA notifications should by-pass certain checks](https://github.com/github/notifyd/issues/439) that are performed within the delivery pipeline (spam-check, notification schedules, etc.). Except for the SAML-check, the public interface of notifyd doesn't provide any tools for integrators to skip those checks.

Current Notifyd pipeline flow:
![image](https://user-images.githubusercontent.com/5173831/138440857-8b622099-244c-47a2-897f-9870f57b86f8.png)
Expected outcome:
![image](https://user-images.githubusercontent.com/5173831/138440790-94aa4d22-4a70-4041-b84b-8d0ee3359712.png)

## Context
In some cases integrators want to skip default checks because they are not relevant for notifications that they are trying to send. Example of this case is 2FA, which wants to do the following:
- they should be sent for all users (spammy, blocked, suspended users)
- they want to be able to send notifications to recipient same as actor
- those notifications are not related to concrete repository, so most of ignore repository checks are not relevant here as well

In 2FA use-case where we want to skip default checks, we have documented checks that we want to skip. You can see more detailed info about skipped checks [in this issue](https://github.com/github/notifyd/issues/439).

## Goals and objectives
Integrators should be able to skip certain default checks in the Notifyd delivery pipeline.

## Assumptions

- We want to keep at least `authzd` checks

## Guiding Principles
* Notifyd shouldn't incorporate domain logic of integrators
