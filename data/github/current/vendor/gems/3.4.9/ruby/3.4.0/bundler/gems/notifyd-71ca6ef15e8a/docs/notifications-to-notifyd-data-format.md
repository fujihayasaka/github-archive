# Newsies to Notifyd data format

## Context

This document describes format of notification concepts in Notifyd data structures.
Notification system has multiple concepts inherited from Newsies: watchers, thread/thread type subscriptions,
notification settings, etc.

Most of them are currently supported by Newsies, however we rely on set of custom data mapping rules to represent
different concepts in Notifyd.

**All values are taken from DB or active Pull requests.**

Please update this document as format changes.

## Format for Watcher subscriptions

Watcher subscriptions are scoped to a repository (see topic) and tagged with a match rule `watch_activity` that has to be present 
on Notify message to match this subscription.

Watcher subscriptions have set of custom fields that allow to fetch subscription based on several criterials:
- repository
- owner user/org
- subscription category

We have defined special tag in custom fields: `watcher_scenario`. 
It acts as aggregation custom field to fetch all subscriptions related to watchers scenario: watchers and thead subscriptions. 



```
{
  "reason": "list_subscription",
  "filters": [
    {
      "subject_type": "any",
      "trigger": "any",
      "reason": "any",
      "match_rules": [
        {
          "attribute": "watch_activity",
          "value": "true",
          "match_rule": "eq"
        }
      ]
    }
  ],
  "topics": [
    {
      "Type": "repository",
      "Value": "123" // repository id from dotcom 
    }
  ],
  "custom_fields": [
    {
      "name": "category",
      "value": "all"
    },
    {
      "name": "watcher_scenario",
      "value": "true"
    },
    {
      "name": "repository_id",
      "value": "123" // repository id from dotcom
    },
    {
      "name": "owner_id",
      "value": "321" // user or org owning a notification subject
    },
    {
      "name": "owner_type",
      "value": "user" // user or organization
    },
    {
      "name": "auto_subscription",
      "value": "true" // true or false - indicates if list subscription was created manually or with auto subscription
    }
  ]
}
```

## Ignore repository setting

Variation of Watch subscriptions are `Ignore` routing settings: they forbid all notifications to come though on a specific repository:

```
{
  "topics": [
    {
      "Type": "repository",
      "Value": "234"
    }
  ],
  "filters": [
    {
      "subject_type": "any",
      "trigger": "any",
      "reason": "any",
      "match_rules": [
        {
          "ID": 0,
          "value": "true",
          "attribute": "watch_activity",
          "RoutingKey": "",
          "match_rule": "eq",
          "RoutingSettingID": 0
        }
      ],
    }
  ],
  "channels": {
    "ALL": {
      "Channel": "ALL",
      "Enabled": false
    }
  },
  "custom_fields": [
    {
      "name": "owner_id",
      "value": "28019954"
    },
    {
      "name": "owner_type",
      "value": "organization"
    },
    {
      "name": "category",
      "value": "all"
    },
    {
      "name": "watcher_scenario",
      "value": "true"
    },
    {
      "name": "repository_id",
      "value": "234"
    }
  ]
}
```

## Thread type subscriptions

Thread type subscriptions are scoped to a repository (see topic) and tagged with a match rule `watch_activity` that has to be present
on Notify message to match this subscription.
Also, Thread type subscriptions matches on `thread_type` in match rules. `thread_type` also has to be present on Notify message. 

Thread type subscriptions have set of custom fields that allow to fetch subscription based on several criteria:
- repository
- thread type
- owner user/org
- subscription category

We have defined special tag in custom fields: `watcher_scenario`.
It acts as aggregation custom field to fetch all subscriptions related to watchers scenario: watchers and thead subscriptions.

```
{
  "reason": "thread_type_subscription",
  "filters": [
    {
      "subject_type": "any",
      "trigger": "any",
      "reason": "any",
      "match_rules": [
        {
          "attribute": "watch_activity",
          "value": "true",
          "match_rule": "eq"
        },
        {
          "attribute": "thread_type",
          "value": "discussion", // thread type: discussion, issue, pull_request, lower case
          "match_rule": "eq"
        }
      ]
    }
  ],
  "topics": [
    {
      "Type": "repository",
      "Value": "123" // id of repository from dotcom
    }
  ],
  "custom_fields": [
    {
      "name": "category",
      "value": "thread_type"
    },
    {
      "name": "watcher_scenario",
      "value": "true"
    },
    {
      "name": "repository_id",
      "Value": "123" // id of repository from dotcom
    },
    {
      "name": "owner_id",
      "value": "321" // user or org owning a notification subject
    },
    {
      "name": "owner_type",
      "value": "user" // user or organization
    },
    {
      "name": "thread_type",
      "value": "discussion"
    }
  ]
}
```

## Thread subscriptions

Thread subscriptions are scoped to a thread (issue, discussion, pr) (see topic) and tagged with a match rule `thread_participant_activity` that has to be present
on Notify message to match this subscription.

Thread subscriptions have set of custom fields that allow to fetch subscription based on several criteria:
- repository
- thread type and id
- owner user/org
- subscription category

```
{
  "reason": "manual",
  "filters": [
    {
      "subject_type": "any",
      "trigger": "any",
      "reason": "any",
      "match_rules": [
        {
          "attribute": "thread_participant_activity",
          "value": "true",
          "match_rule": "eq"
        }
      ]
    }
  ],
  "topics": [
    {
      "Type": "issue", // we scope thread subscriptions by thread type and thread id instead of repo
      "Value": "519872236"
    }
  ],
  "custom_fields": [
    {
      "name": "category",
      "value": "thread"
    },
    {
      "name": "newsies_thread_subscription_id",
      "value": "2768523949" // id of newsies thead subscription
    },
    {
      "name": "repository_id",
      "Value": "123" // id of repository from dotcom
    },
    {
      "name": "owner_id",
      "value": "321" // user or org owning a notification subject
    },
    {
      "name": "owner_type",
      "value": "user" // user or organization
    },
    {
      "name": "thread_type",
      "value": "issue" // thread type, issue, pull request, discussion
    },
    {
      "name": "thread_id",
      "value": "519872236" // id of the issue thread
    }
  ]
}
```

## Ignoring threads settings

Ignore Thread routing settings are scoped to a thread (issue, discussion, pr) (see topic) and tagged with a match rule `thread_participant_activity` that has to be present
on Notify message to match this subscription.

Also, we make use of  `notify_muted` reason group and `not_in_reason_group` match rule. It means that thread will be ignored 
for all recipients except if they have special case of reasons for example `mention`. 

Ignore subscriptions have set of custom fields that allow to fetch subscription based on several criteria:
- repository
- thread type and id
- owner user/org
- subscription category

```
{
  "topics": [
    {
      "Type": "issue", // we scope thread ignore routing setting by thread type and thread id instead of repo
      "Value": "519872236"
    }
  ],
  "filters": [
    {
      "subject_type": "any",
      "trigger": "any",
      "reason": "any",
      "match_rules": [
        {
          "attribute": "thread_participant_activity", // ignored is scriped to thread_participant_activity only
          "value": "true",
          "match_rule": "eq"
        },
        {
          "attribute": "",
          "value": "notify_muted",
          "match_rule": "not_in_reason_group" // we want to allow certain reasons to override ignore setting
        }
      ]
    }
  ],
  "channels": {
    "ALL": {
      "Channel": "ALL", // we disable ALL channels, without enumarating them
      "Enabled": false
    }
  },
  "custom_fields": [
    {
      "name": "category",
      "value": "thread"
    },
    {
      "name": "thread_type",
      "value": "issue" // thread type, issue, pull request, discussion
    },
    {
      "name": "thread_id",
      "value": "519872236" // id of the issue thread
    }
    {
      "name": "owner_id",
      "value": "321" // user or org owning a notification subject
    },
    {
      "name": "owner_type",
      "value": "user" // user or organization
    },
    {
      "name": "repository_id",
      "Value": "123" // id of repository from dotcom
    }
  ]
}
```

## CI Activity setting

CI activity routing settings are scoped globally (see topic) to a `reason`. It means that Notify messages with `reason` matching
to CI activity `ci_activity` or `approval_requested` will match to CI activity settings.

For case when we want to match only failed `ci_activity` events we use additional `match_rule` to filter out only failed events.
We have only one `custom_field` on this routing setting.


```
{
  "topics": [
    {
      "Type": "any",
      "Value": "any" 
    }
  ],
  "filters": [
    {
      "subject_type": "any",
      "trigger": "any",
      "reason": "ci_activity",
      "match_rules": [
        {
          "attribute": "failed",
          "value": "true",
          "match_rule": "eq"
        }
      ]
    },
    {
      "subject_type": "any",
      "trigger": "any",
      "reason": "approval_requested",
      "match_rules": [
        {
          "attribute": "failed",
          "value": "true",
          "match_rule": "eq"
        }
      ]
    }
  ],
  "custom_fields": [
    {
      "name": "delivery_group",
      "value": "ci_activity"
    }
  ],
  "channels": {
    "PUSH": {
      "Channel": "PUSH",
      "Enabled": false
    },
    "EMAIL": {
      "Channel": "EMAIL",
      "Enabled": true
    }
  }
}
```

## Participating setting

Participating routing settings are scoped globally (see topic) and limited to Notify events with `thread_participant_activity` match rule.
It's used to turn off EMAIL/WEB notifications for participating notifications from user notification settings.

We have added additional match rule `category` to differentiate it from other settings.

```
{
  "topics": [
    {
      "Type": "any",
      "Value": "any" 
    }
  ],
  "filters": [
    {
      "subject_type": "any",
      "trigger": "any",
      "reason": "any",
      "match_rules": [
        {
          "attribute": "thread_participant_activity",
          "value": "true",
          "match_rule": "eq"
        }
      ]
    },
  ],
  "custom_fields": [
    {
      "name": "category",
      "value": "user_setting_watcher_activity"
    }, 
  ],
  "channels": {
    "EMAIL": {
      "Channel": "EMAIL",
      "Enabled": true
    }
  }
}
```

## Watching setting 

Watching routing settings are scoped globally (see topic) and limited to Notify events with `watch_activity` match rule.
It's used to turn off EMAIL/WEB notifications for watch notifications from user notification settings.

Consider `participant` value for `not_in_reason_group` match rule. It means that disabling `Watching` setting will not affect
`participants` notifications. They have to be disabled separately.

We have added additional match rule `category` to differentiate it from other settings.


```
{
  "topics": [
    {
      "Type": "any",
      "Value": "any" 
    }
  ],
  "filters": [
    {
      "subject_type": "any",
      "trigger": "any",
      "reason": "any",
      "match_rules": [
        {
          "attribute": "watch_activity",
          "value": "true",
          "match_rule": "eq"
        },
        {
          "attribute": "",
          "value": "participant",
          "match_rule": "not_in_reason_group"
        }
      ]
    },
  ],
  "custom_fields": [
    {
      "name": "category",
      "value": "user_setting_watcher_activity"
    },
    {
      "name": "scenario",
      "value": "user_settings"
    },
  ],
  "channels": {
    "EMAIL": {
      "Channel": "EMAIL",
      "Enabled": true
    }
  }
}
```

