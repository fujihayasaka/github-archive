# Reasons matching in routing settings

## Context

Routings settings are applied per recipient considering the following variables:
1. Message data, more precisely, fields that we use for matching: subject type, trigger, attributes and topics.
2. Reasons why recipient is getting notified. Reasons may come from the notification message (explicit recipients) as well as from the subscriptions.

The advantage of this approach is that we can flexibly configure notification channels using this data.
However, with this approach settings may contradict each other.

For example we have notifications marked with attribute `watch_activity` and notifications marked with attribute `thread_participant_activity`. The thread participant activity is a subset of watch activity. Also, if notification is marked
with the `thread_participant_activity` attribute it does not mean that every recipient is going to be notified because they're subscribed to a thread. Some of them will get notified because they are watching the repository (`watch_activity`).

In this way we can get settings that match the same notifications but has different channels configured. Currently we are using simplified approach: settings that disable certain channels always take a priority. It is not working however for the global notification settings for watch activity and thread participants:

![image](https://user-images.githubusercontent.com/1885174/205280853-c06c1cb3-c871-4b8d-a537-32a3c984d501.png)


Why? Let's imagine that user has a setting that disables Emails for watch activity notifications. However, they still want to receive notifications for the threads they are participating in.

This user is subscribed to a repo, and also subscribed to a thread in this repo. If our current logic is applied the user will not get any notifications for this thread because this notifications will be disabled by a routing setting that is applied to watch activity notifications (remember that thread notifications is a subset of watch activity notifications).

This is not the behavior we want so we need somehow to prioritize the settings or create settings in a way to avoid conflict.

This proposal is exploring solutions to this problem.


## More flexible rules for reasons matching

As mentioned above we match settings by notification message data and reasons.

We use message attributes to tag notification messages, for example with `thread_participant_activity` and `watch_activity` attributes. This way integrator have full control of the subset of message that are marked with certain tags. If integrator wants to include/exclude some events from the `watch_activity` it can be done without changing subscriptions and settings stored in database.

However, we do not have the same mechanism for reasons. We can specify one reason per routing setting and we do not have complex rules to match them. Our current logic of matching the routing setting with reason: if recipient has the reason configured in setting among notification reasons, return true.

In order to disable emails for watch activity, except when user is a thread participant, we need to be able to create a setting that either
1. matches all the reasons except reasons for thread participants (manual, mention, comment etc) and message is tagged as `watch_activity`.
2. matches if the recipient has only reason `list_subscription`, `thread_type_subscription` or both and no other reasons, and the message is tagged as `watch_activity`.

None of these scenarios are supported by current matching system.

## Solution: Add reasons matching to the routing settings matcher

Currently we support only `eq` and `ne` match rules for notification message attributes, but we can add custom match rules that are able to apply the filtering logic we need.

Such rule will accept the following arguments:
1. Recipient id
2. Recipient reasons
3. Notification message match fields
4. `value` that it needs to compare the result to.

Currently subscriptions and routing settings share most of the matching logic. Subscriptions matching does not consider reasons by design, because subscriptions are the source of reasons. Despite that subscriptions and routing settings are using the same schema, reasons have different meaning for routing settings and subscriptions.

For a subscription reason means literally the reason why user is subscribed. These reasons are used on `CalculateRecipients` phase to make `recipientIdsToReasons` hash map with potential recipients and set of reasons why each of them is notified.

Reason in routing setting is one of the filtering criteria.

When we create a subscription with reason `manual` it means that user manually subscribed to a thread. When we create a routing setting with reason `manual` it means we want to apply this routing setting only if one of the reasons user is notified is `manual`.

This reasons filtering logic we apply in 2 places:


1. When applying default routing settings

```go
func applySettingsToChannels(settings []Setting, matchFields datastructures.MessageMatchFields, reasons []string, channels match_engine_dto.ChannelsMap) {
	var matched bool
	for _, setting := range settings {
		matched = matchSetting(setting, matchFields, reasons)

		if matched {
			for _, channel := range setting.Channels {
				channels[channel.Channel] = &match_engine_dto.Channel{Channel: channel.Channel, Enabled: channel.Enabled}
			}
		}
	}
}

func matchSetting(setting Setting, matchFields datastructures.MessageMatchFields, reasons []string) bool {
	return (setting.Reason == "" || contains(reasons, setting.Reason)) &&
		(setting.SubjectType == "" || setting.SubjectType == matchFields.SubjectType) &&
		(setting.Trigger == "" || setting.Trigger == matchFields.Trigger) &&
		(len(setting.MatchRules) == 0 || attributesMatch(setting.MatchRules, matchFields.Attributes))
}
```

2. When applying stored routing settings

```go
func (s *SettingsService) applyStoredChannels(routingSettingsMatchEntries []*match_engine.MatchedEntry, reasons []string, channelsToNotify match_engine_dto.ChannelsMap, enabled bool) match_engine_dto.ChannelsMap {
	all := false
	for _, matchEntry := range routingSettingsMatchEntries {
		for channelName, channel := range matchEntry.Channels {
			if !reasonsForRecipientAreMatched(matchEntry.Reason, reasons) {
				continue
			}
			if channel.Enabled == enabled {
				if channelName == "ALL" {
					all = true
				} else {
					channelsToNotify[strings.ToUpper(channelName)] = channel
				}
			}
		}
	}
	if all {
		for name := range channelsToNotify {
			channelsToNotify[name].Enabled = enabled
		}
	}

	return channelsToNotify
}
```

The logic of applying routing settings by reasons are very unflexible because it's hardcoded and cannot be configured by integrator: if one of the reasons for recipient matches the reason in routing setting, apply this routing setting.

We need a way to customize this logic to apply the rules mentioned above. We have a mechanism of match rules but currently it is applied only to message attributes. We can extend it to support reasons as well.

The main problem here is that the logic of filtering by match rules are shared by subscriptions and routing settings. We do not need filtering by reasons in subscriptions (we do not even know reasons during subscriptions matching phase) so we have to decouple matching for routing settings and subscriptions. Method `filterByMatchRules` currently used by both services can be modified for routing settings to add custom reasons matching.

The other question is: How to configure reasons matching?

If user opts out of receiving emails for watch activity we will have to avoid potential conflict with thread participant activity settings. We can define custom match rules that would examine `reasons` and apply custom logic.

To solve routing settings conflict between watch activity and thread participant activity settings we can create a custom match rule that determines if the recipient is a participant of the thread.

For that we can create a config that defines certain reasons groups and a custom match rule that checks recipient reasons against the group.

Example for `reasonGroups` configuration:

```
reasonGroup:
    participant:
        - mention
        - manual
        - author
        - comment
```
Match rule to check if one of the recipient reasons is in a reason group:

```
checkInReasonGroup(config, recipientId, reasons, matchFields, compareTo)
    return reasons.intersectWith(config["reasonGroup"]["participant"])
```

If user opts out of receiving emails for watch activity we can create the following routing setting:

```ruby
Notifyd::Proto::RoutingSettings::RoutingSetting.new(
          user_id: user.id,
          topics: [{type: "any" value: "any"}],
          filters: [
              {
               match_rules:  [
                  {type: "attribute", attribute: "watch_activity", value: "true", match_rule: "eq"},
                  {value: "participant", match_rule: "in_reason_group"},
               ]
              }
          ],
          channels: [{name: "EMAIL", enabled: false}],
          custom_fields: [
                  {name: "watch_activity", value: "true"},
           ]
      )
```

In our case this rule returns false (no match) if at least one of the recipient reasons is a thread participant reason.


## Bonus chapter: solving ignore setting and direct mention problem

Recently we've decided on the [proposal](https://github.com/github/notifyd/blob/routing-settings-reasons-matching/docs/proposals/2022-11-15-ignore-thread-setting.md) for "ignore thread" setting.

Instead of the solution proposed there we can use reasons matching to bypass ignore thread setting.

We can define `notify_muted` reason group with the only `mention` reason there:


```
reasonGroup:
    notify_muted:
        - mention
    participant:
        - mention
        - manual
        - author
        - comment
```

In order to do that we create a custom match rule (pseudocode):

```
checkNotInReasonGroup(config, recipientId, reasons, matchFields, compareTo)
    reasonGroup = compareTo
	return !reasons.intersectWith(config["reasonGroup"]["notify_muted"])
```

Then we create the following ignore setting (when user unsubscribes from a thread):

```ruby
Notifyd::Proto::RoutingSettings::RoutingSetting.new(
    user_id: 1,
    name: "ignore",
    topics: [{type: "issue", value: "456"}],
    filters: [{
            match_rules: [
                {attribute: "thread_participant_activity", value: "true", match_rule: "eq"},
                {value: "notify_muted", match_rule: "not_in_reason_group"}
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

In this way the setting will not match when user is directly mentioned, therefore directly mentioned users will still be notified.

### Advantages
- does not require any fundamental changes in the system
- relatively quick to implement
- similar rule can be added to handle the case of "ignore thread" setting, where we need to disable notifications for all the
reasons except mention.
- if we change the definition of a participant we don't have to update stored settings in db

### Disadvantages:
- we're taking dotcom logic to Notifyd, but we extract reason groups into configuration, so it can be an acceptable tradeoff. Passing reasonGroups as part of the event message could be also an option
- can be harder to understand than simple `eq` and `ne` rules
- the way to avoid intersection between two settings is not straightforward
- requires refactoring of current logic

## Summary

This method has its pros and cons. I like that it fits the way our matching engine works and we do not need to do any modifications in the logic on database level. The mechanism of reason matching will make it possible to resolve conflicts between settings that match the same notification messages.