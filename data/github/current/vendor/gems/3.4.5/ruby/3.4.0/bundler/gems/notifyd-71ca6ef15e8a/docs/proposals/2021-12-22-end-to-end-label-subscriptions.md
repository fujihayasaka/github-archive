# [Proposal] End-to-end label subscriptions MVP

## Overview

As outlined in the [brief](../proposals/end-to-end-label-subscriptions.md), we would  like to provide users with an interface to subscribe/unsubscribe to/from a label.

For that, we need three components:

1. API in Notifyd that supports three operations:
 - storing a subscription
 - deleting a subscription
 - getting subscriptions to certain topics for a user
2. UI to subscribe to labels
3. Way to integrate monolith with Notifyd API.

Expected outcome:

![image](https://user-images.githubusercontent.com/1885174/146965849-245e1cff-2aa6-4ba2-8aa0-c3ece80e4a0b.png)

This document is aiming to describe the solution and explain architectural decisions and tradeoffs.

## Proposed solution

### User Interface

UI should have the following functionality:

1. Allow user to pick labels from those already existing in a repository
2. Display labels that user already subscribed to
3. Allow user to remove labels they don't want to be subscribed to anymore.

UI should be visible only to staff members that opted in for this functionality.

#### Custom watch repo settings

According to design mockups we will place label subscription UI on the "Watch repo" dropdown under "Custom".

[![Video](https://user-images.githubusercontent.com/1885174/146945556-6b5abe57-876d-418e-ab3d-3977ab50735e.png)](https://user-images.githubusercontent.com/1885174/146945022-28a84251-72ba-49ae-b005-fe662498a343.mov)

We can use `Primer::LabelComponent` to display labels user subscribed to.

#### Label picker

To enable user to subscribe to labels we will use similar picker that currently exists in issue sidebar. However, we do not have a reusable component for it. We can create one based on the logic of issue sidebar dropdown: [1](https://github.com/github/github/blob/master/app/views/issues/sidebar/_menu.html.erb), [2](https://github.com/github/github/blob/master/app/views/issues/sidebar/_labels_menu_content.html.erb)

We need to make sure to defer loading of a dropdown which means that list of labels will be loaded only when dropdown is shown. For that we will be using `<details-menu>`  tag.

#### Action handler

We need to wire label picker with the action that will be accepting the list of labels and adding/removing subscriptions based on this list, similar to [update action](https://github.com/github/github/blob/007a140b403cc9afbb16223cabbc734e49fd08c2/app/controllers/issues/labels_controller.rb#L23) in issue labels controller.

#### Getting the list of labels user subscribed to

We need to get the list of labels user subscribed to in order to display them in a watch dropdown and in a label picker dropdown.

The problem here is that in Notifyd we store the following info for a label subscription: topic_type "label", topic_value "<label_id>" and a user_id. We could fetch all the subscriptions with the type "label" but we need only labels that belong to a current repo. We do not have any information about the repo in Notifyd.


**Alternative 1**

The first  solution is to get the list of label ids for the current repo and pass it to Notifyd API to search for subscriptions that match these label ids (topic values).

_Advantages_

It's easy to implement and does not require any changes in a current architecture.

_Drawbacks_

The problem I foresee is with repos that have a lot of labels: we would need to do a round trip to Notifyd with a big-sized chunk of data (list of all labels). We would need to rethink this approach in the future and think about saving additional context data for subscription without leaking integrator logic to Notifyd.

**Alternative 2**

Second solution will require to iterate on subscriptions service design we currently have. Currently we store the `topic_type`, `topic_value` and `user_id` for subscription. We can ask integrators to populate additional information when creating a subscription in notifyd: subscription attributes. These will be later used to filter out subscriptions. In our case we need to filter out subscriptions that belong to a repository. Which means we can populate an attribute with key `repository_id` and id of a repository that label belongs to as a value when creating a label subscription.

We will store the subscription itself in a subscriptions table, but in addition we will save an attribute (`repository_id` in this case) in a separate table `subscription_attributes` with the following struncture:

| column   |      type      |  description |
|----------|:-------------:|------:|
| subscription_id |  bigint | Id of a subscription |
| key |    string |  Attribute name |
| value | string |   Attribute value |

We will create two indexes: for `subscription_id` column and for `(key, value)` columns. In this way we will be able to fetch only subscriptions that relate to a particular repository and database will take care of filtering.

Sample ruby client call to store the subscription:

```ruby
subscriptions = Notifyd::Proto::SubscriptionsClient.new(@connection)
result = subscriptions.create(
        Notifyd::Proto::Subscriptions::CreateRequest.new(
            user_id: 1,
            topics: [{type: 'label', value: '1'}],
            attributes: [{key: 'repository_id', value: '3'}])
      )
```

Sample ruby client call to fetch label subscriptions for a repo:

```ruby
subscriptions = Notifyd::Proto::SubscriptionsClient.new(@connection)
result = subscriptions.get(
        Notifyd::Proto::Subscriptions::GetRequest.new(
            user_id,
            topics: [{type: 'label'}],
            filter_by_attributes: [{key: 'repository_id', value: '3'}]),
        options,
      )
```

This will turn into this query on Notifyd's side:


```sql
SELECT * FROM subscriptions
    INNER JOIN subscription_attributes on subscription.id = subscription_attributes.subscription_id
    WHERE
    subscription.user_id = 1 AND
    subscription.topic_type = 'label' AND
    subscription_attributes.key = 'repository_id' AND
    subscription_attributes.value = '3'
```


_Advantages_

We don't need to pass long list of topics to Notifyd, instead we pass the attribute (repository_id) and Notifyd will do necessary filtering before sending found subscriptions back to the monolith.


_Drawbacks_

This adds a complexity for the integrator that should specify all the necessary data on the stage of creating a subscription in order to be able to use this data later to filter subscriptions.


### Notifyd subscriptions API

Notifyd subscriptions API should have the following operations:

1. Creating a subscription. This operation takes user and a topic as an input.
2. Deleteing a subscription. This operation takes user and a topic as an input.
3. Getting list of subscriptions. This operation takes a user and list of topics as an input.

The proposal is to use Twirp RPC framework for API.
There are several reasons for that:

1. Twirp uses protobuf which is a protocol with minimal overhead, especially compared to HTTP/Rest.
2. We already use Twirp endpoints in Notifyd.
3. We already communicate with Notifyd from monolith via Twirp.
4. We use Twirp in other services in GitHub (authzd, internal status service as examples).

We will create Subscriptions service with the following endpoints:

```
service Subscriptions {
    rpc Get(GetRequest) returns (GetResponse);
    rpc Create(CreateRequest) returns (StatusResponse);
    rpc Delete(DeleteRequest) returns (StatusResponse);
}

message Topic {
    string type = 1;
    string value = 2;
}

message Attribute {
    string key = 1;
    string value = 2;
}

message CreateRequest {
    int32 user_id = 1;
    repeated Topic topics = 3;
    repeated Attribute attributes = 3;
}

message GetRequest {
    int32 user_id = 1;
    repeated Topic topics = 3;
    repeated Attribute filter_by_attributes = 3;
}

message DeleteRequest {
	int32 user_id = 1;
    repeated Topic topics = 3;
}

message GetResponse {
    repeated Subscription subscriptions = 1;
}

message StatusResponse {
    string error = 1;
}

message Subscription {
    int64 id = 1;
    int32 user_id = 2;
    string topic_type = 3;
    string topic_value = 4;
}

```


### Integration of monolith with Notifyd subscriptions API

We need to create a client to communicate with Notifyd API from the dotcom monolith.
Client shall implement all three operations that is supported by subscriptions API.

As we have Twirp service definition we can generate a Ruby client to communicate with defined endpoints. This will be the part of Notifyd ruby client that we already have and that is already used in monolith.


### Feature flag

UI and backend handler in the monolith that is responsible to store and remove subscriptions will be guarded by `notifyd_label_subscriptions` flag.


