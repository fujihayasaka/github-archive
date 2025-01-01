# Step by step guide for integrators (notifyd)

## How to Implement mobile push notifications

This is a high-level guide to implement a new notification type with `notifyd`.

## Requirements and Considerations

#### General requirements
- Define an [`authzd`](https://github.com/github/authzd) policy according to the notification type needs. Does the user have the permissions to read the notification? ([e.g. Policy that allows a user to receive a notification for an issue comment](https://github.com/github/authzd/blob/master/config/policies/notifications.json#L8))
- Check the [required parameters](https://github.com/github/github/blob/master/packages/notifications/app/models/notifyd/notify_publisher.rb#L86-L117) to deliver notifications with `notifyd`.
- Define the [conditions](https://github.com/github/github/blob/master/app/models/notifyd/issue_adapter.rb#L6) for the notifications to be delivered.

#### Is this a new implementation?
  - You will need [`notidyd` feature flag](https://github.com/github/github/blob/master/packages/notifications/app/models/notifyd/issue_adapter.rb#L18-L20) for a safe rollout.

## Steps
  
 #### 1. In which events do you want to send a notification?
  Review **instrumented events** or create new ones if necessary. The events define when the notification should be sent by Notifyd. If some data is missing, add the data needed to send the notifications (e.g. [discussions.update](https://github.com/github/github/blob/master/app/models/discussion.rb#L1321-L1326)).
  #### 2. Create a **subject adapter** (e.g. [Issue Adapter](https://github.com/github/github/blob/master/packages/notifications/app/models/notifyd/issue_adapter.rb)) for the notification type and define:
  - `notification_id` to identify the notification. This field is mandatory.
  - Are there any conditions for not sending the notification? Use the [`matches?` method](https://github.com/github/github/blob/master/packages/notifications/app/models/notifyd/issue_adapter.rb#L10-L12). This method is not mandatory as it is defined as [`true` as default](https://github.com/github/github/blob/master/packages/notifications/app/models/notifyd/subject_adapter.rb#L116-L118)
  - Feature flags
  
  You can also define other needed attributes that will depend on the notification type. The definition of each of them can be found in the [`NotifyPublisher` publish method documentation](https://github.com/github/github/blob/master/packages/notifications/app/models/notifyd/notify_publisher.rb#L86-L117):
  `authzd_attributes`, `saml_enforcement`, `mobile_layout`, `explicit_recipients`
  
  #### 3. Create **Subscription** methods for the events and call [`Notifyd::NotifyPublisher`](https://github.com/github/github/blob/master/app/models/notifyd/notify_publisher.rb) to publish the message to `notifyd` service to be delivered. (e.g. [`issue.create` subscription](https://github.com/github/github/blob/master/config/instrumentation/hydro/subscriptions/notifyd_issues.rb#L53-L73)). 


  Notifyd [consumes the message published](https://github.com/github/notifyd/blob/main/internal/mobile/serbice.go#L85) and delivers the notification.


### Examples

This is an example of push notification payload processed by  `notifyd`, [from `mobile_layout` method](https://github.com/github/github/blob/master/packages/notifications/app/models/notifyd/mobile_renderer/discussion.rb#L16-L32):

```
{
  actor_login: "@mikrobi",
  sub_title: "team-discussions/notifications-go-test-repo #36",
  body: "Hey @jezcommits and @franciscoj",
  url: "https://starter-workflow-route-controller.review-lab.github.com/team-discussions/notifications-go-test-repo/discussions/36",
  thread_id: "team-discussions/notifications-go-test-repo/discussions/36",
  thread_type: "discussion",
  avatar_url: "https://avatars.githubusercontent.com/u/1234567?v=4",
  author_profile_name: "mikrobi",
}
```

<img width="362" alt="Screenshot 2021-08-30 at 13 49 00" src="https://user-images.githubusercontent.com/8514581/131336695-45709485-e166-4e89-9f56-a940ceab85f8.png">

## Troubleshooting - Are notifications not being sent?
- Check `authzd` policy is not restricting the user to receive/read the notification type ([e.g. do the policy rules allow the user to receive a notification for an issue mention?](https://github.com/github/authzd/blob/master/config/policies/notifications.json#L9-L35))
- Check SAML authentication
  - Is the user allowed to receive notifications [by settings](https://github.com/github/github/blob/master/app/api/internal/twirp/notifications/notifyd/v1/notifyd_api_handler.rb#L27)?
  - Is the user allowed to receive notifications [by schedule](https://github.com/github/github/blob/master/app/api/internal/twirp/notifications/notifyd/v1/notifyd_api_handler.rb#L28)?
  - [Is the user a member of the organization?](https://github.com/github/github/blob/master/app/api/internal/twirp/notifications/notifyd/v1/notifyd_api_handler.rb#L33)
- Is the user ignoring the repository?
