# Unsubscribe and mute functionality for threads in Notifyd

## Context

By now we have only moved Gist thread notifications to Notifyd. We implemented unsubscribe functionality as follows: when a user clicks "Unsubscribe" button in Gist thread page we make 2 calls to Notifyd: to remove existing subscription (if any) and to add "ignore" setting to prevent any non-subscription related notifications.

We need the second one because many notifications are sent not because user is explicitly subscribed, but for example if user has been mentioned, user is an author of the thread or commented on a thread. In these cases we do not have a subscription, so the routing setting that explicitly "mutes" notifications for a thread is needed.

The routing setting we currently save looks like this:

```ruby
Notifyd::Proto::RoutingSettings::RoutingSetting.new(
    user_id: 1,
    name: "ignore",
    topics: [{type: "gist", value: "456"}],
    filters: [{
          reason: "comment",
          subject_type: "any",
          trigger: "any"
        },
        {
          reason: "author",
          subject_type: "any",
          trigger: "any"
        },
        {
          reason: "manual",
          subject_type: "any",
          trigger: "any"
        }
    ],
    channels: [{name: "ALL", enabled: false}],
    custom_fields:       [
        {name: "category", value: "thread"},
        {name: "thread_type", value: "gist"},
        {name: "thread_id", value: "456"},
        {name: "owner_type", value: "user"},
        {name: "owner_id", value: "123"},
      ])
```

In `filters` section we specify three filters - each for every reason we want to mute. This is done in this way because we do not want to mute mentions. It means that ignore settings should not match users that notified with the reason `mention`, to do that we specify all the reasons possible for the Gist thread except `mention`.

There are two main flaws in this approach:
1. It can fall apart if we add subscriptions or events with new reasons. In this case we will have to write a transition to backfill the data.
2. It does not work when user is an author/commenter of the thread or manually subscribed and mentioned at the same time. In this case we will mute notification because we will apply routing settings for comment, author and manual reasons which disable notifications.

We need a way to store "ignore" settings that are devoid of these shortcomings.

## Proposed solution

### Ignore routing setting data

Instead of specifying reasons in routing setting filter we do matching by the attribute thread_participant_activity. All the thread notification events are marked with this attribute and it is controlled on a dotcom's side. We can exclude/include events from thread activity without changing the data stored for ignore routing settings. This solves first problem.

We also need to make sure that mentions are not ignored. In routing settings match rules we can specify attribute `notify_muted` with user id as value (where user id is an id of a user that owns a setting).
As a result routing setting will look like this:

```ruby
Notifyd::Proto::RoutingSettings::RoutingSetting.new(
    user_id: 1,
    name: "ignore",
    topics: [{type: "issue", value: "456"}],
    filters: [{
            match_rules: [
                {attribute: "thread_participant_activity", value: "true", match_rule: "eq"},
                {attribute: "notify_muted", value: "1", match_rule: "ne"}
            ]
        },
    ],
    channels: [{name: "ALL", enabled: false}],
    custom_fields:       [
        {name: "category", value: "thread"},
        {name: "thread_type", value: "issue"},
        {name: "thread_id", value: "456"},
        {name: "owner_type", value: "organization"},
        {name: "owner_id", value: "123"},
        {name: "repository_id", value: "765"}
      ])
```

### Converting the data for Gists

We will have to write a transition that will go through all the unsubscribe settings for Gists and convert them to a new format.


### Dotcom changes

We need to extract mentionees from issue comment (or a subject content in general) and add an attribute to the event per every mentioned user (same logic as for `has_label` attribute).

Sample code:
```ruby
  mentionees.each do |mentionee|
    attributes << {name: "notify_muted", value: mentionee.id.to_s}
  end
```

Same logic is applied to team mentions.


Also, we need to change the logic of displaying unsubscribe/subscribe button. Now it accounts only for the old unsubscribe setting format.

### Changes in Notifyd

Currently we support only `eq` match rules. We will have to add support of `ne` match rule to the matcher.

### Drawbacks

We need to duplicate mentionees in two places in the same message. We need to do this for multiple subjects because behavior is the same everywhere in dotcom.
To mitigate this we can add `notify_muted` attributes on Notifyd's side, though I see several drawbacks of this solution:
1. Leaking dotcom logic to Notifyd
2. Modification of input (event message).
3. "Magical" behavior: it is not clear for example why integrator when saving a setting need to specify `notify_muted`  attribute for ignore setting.

I propose to fill the attributes on the dotcom side for now and then think of the appropriate interfaces for integrators.


