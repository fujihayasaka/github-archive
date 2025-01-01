# Channel settings


## Context

Currently we do not store channels in the database. We have the logic related to channels coded into the logic of the consumer which makes channels not configurable.

We also decide on channels only when we retrieve routing settings. But according to design mockups we need to account for a possibility to configure channels per subscription (see image below). Current schema does not support this.

![image](https://user-images.githubusercontent.com/1885174/154848039-9d1130e9-b36b-4182-8268-8e678774c257.png)

In this proposal we will concentrate on channels for routing settings but the solution should not block the possibility to configure channels per subscription.

This proposal describes the solution to store channels that will be serving routing settings subsystem and potentially subscriptions system in the future.


## Proposed solution

1. We will create a new channels table that `routing_settings` table and potentially `subscriptions_v2` table can reference as one to many:

`Routing setting ---> * Channels`

| column  | type       | description|
|---------|------------|------------|
| id      | int        |            |
| ref_type| varchar(20)| subscription or routing setting  |
| ref_id  | int        | subscription or routing setting id |
| channel | varchar(20)| name of the channel (email, push, web etc) |
| enabled | bool       |            |

Channels maybe abscent as well which means that channel is not set and the decision will be made based on default settings.
Default settings are currently [hardcoded per reason](https://github.com/github/notifyd/blob/bd1bcf5fe25da9d9a845abb14a48eef57f7937aa/internal/pkg/routing_settings/routing_settings_service.go#L135-L148). In the future we'll have separate proposal on how to store them.

2. Integrators will specify list of enabled channels when making the request for Twirp API for routing settings:


Sample request for routing settings:

```ruby
subscriptions = Notifyd::Proto::RoutingSettingsClient.new(@connection)
result = subscriptions.create(
        Notifyd::Proto::RoutingSettings::CreateRequest.new({
            user_id: 1,
            reason: "ci_activity",
            channels: {email: true, push: false},
            filters: [
                {
                    subject: "CheckSuite",
                    trigger: "completed",
                    match_rules: [
                        { attribute: "conclusion", value: "failed", match: "eq" },
                    ]
                }
            ]
        })
    )
```

3. We will save channels along with other data to details column of `meta_subscriptions` and  to `channels` table that routing setting will be referencing.

4. We will select channels for all routing settings that match engine returned.

5. `RouteRecipientsToChannelsStage` will apply channels from routing settings (if any matched routing settings found for the event) and make a final decision about what channels to use for notifications for each recipient.


Chart showing the steps described above:

![image](https://user-images.githubusercontent.com/1885174/171599966-782c678a-2c26-4844-8e98-59ebd09b6a87.png)

**Pros:**
- No records duplication
- If we really want we could query for channels information separately on consumer side, nothing is really stopping us from splitting channels from query process
- Channels model can grow in this case (mute functionality, special channel delivery rules, etc)
- If we decide to add/delete channel we don't need to create multiple of records for existing subscriptions and routing settings

**Cons:**
- we may deal with extra join in database table, this will further complicate the logic of matching engine
- we will need slight refactor of database model: Notify: true/false should be then property of Channel not RoutingSetting


## Explored alternatives

### Alternative 1

Adding a column to routing_settings table that will contain infor about one channel. Therefore we will be creating routing_setting per every channel.

**Pros:**
+ easy to integrate and reason about routing settings
+ de-normalized routing settings data store

**Cons:**
- we would need to duplicate routing settings records
- what is worse match_rules records now reference single subscription/routing settings table.
It means that match rules records may also need to be duplicated.

### Alternative 2

Adding new column channels on tables `subscriptions_v2` and `routing_settings`. This column will be JSON blob looking like this:

```json
{
    "email": true,
    "push": false
}
```

Every channel switch can take 3 values: not set, true and false. Abscence of channel in a JSON structure means that nothing is specified about the channel for a particular subscription/routing setting.


**Pros:**
- Efficient storage
- No added joins
- No record duplication
- Works well with both settings and subscriptions model
- Easier to understand

**Cons:**
- Cannot do selects by channels in database. We don't have this scenario though so we can ignore this disadvantage.
- If two updates are happening simultaneously phantom read can occur and some values in json can be overriden.


