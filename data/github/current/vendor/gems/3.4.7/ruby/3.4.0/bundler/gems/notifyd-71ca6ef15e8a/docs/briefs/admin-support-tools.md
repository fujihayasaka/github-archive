# Brief: Admin and Support tooling


## Problem Statement

As we are migrating more and more data to be owned by the notifyd platform, the
number of times we (the notifications team) as well as the support team need to
be able to take a look at the current state of data for support and incident
related things also rises. In order to make this more efficient we need admin
and support tooling at least similar to what we have on the newsies side.

## Context

One of the very basic pieces of information we need to still provide is a
users notification settings:

<img width="464" alt="Screenshot_2022-08-01_at_12 01 53" src="https://user-images.githubusercontent.com/68183/182602006-619a50f9-05f1-4aaf-93c8-eb6cd00d736f.png">

In addition to that we also have a notifications view on the repository in
stafftools that gives us an overview of recent notifications, along with the
delivery channel as well as reason:

<img width="624" alt="Screenshot_2022-08-03_at_13 41 51" src="https://user-images.githubusercontent.com/68183/182602075-641f052d-6023-46d6-ba86-9b940ac33a15.png">

There are also some additional use cases that we don't currently have in
stafftools but come up frequently when debugging and will come up more in the
future such as:

- view users routing settings
- view users subscriptions
- view users most recently delivered notifications


Some of these things might still work as we are exposing them to the monolith
via notifyd APIs. And depending on how we retrieve this in stafftools we might
still see them. However as we are changing the model of how notifications work
with notifyd we are bound to break some of this interaction.
