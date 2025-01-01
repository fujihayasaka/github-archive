# Support html templating for emails being sent via notifyd

## Problem statement

We want to support adding html templates for emails being sent via notifyd. Our current emails look like this:

![image](https://user-images.githubusercontent.com/8514581/150115427-038f3881-590b-4d0a-82a5-f4f364ab4821.png)

To support email templating for emails sent via notifyd, we want to have an appearance like the [email layout](https://github.com/github/github/blob/master/app/views/mailers/layouts/primer_layout.html.erb) that lives in the monolith,
and has the [following basic structure](https://thehub.github.com/engineering/development-and-ops/email/#the-primer-email-layout): header, body and footer.

We are intending to do this to allow the following goals in the long term:
- Improve user experience
- Make it easy for integrators to create their own templates by adding custom header, body and footer and allowing them to use Primer components

### Expected outcome:

Our target is to deliver emails with a basic structure close to the [Primer email layout](https://github.com/github/github/blob/master/app/views/mailers/layouts/primer_layout.html.erb):

![image](https://user-images.githubusercontent.com/8514581/151193535-400e5bdb-b4e4-4f81-9be0-f5efeb3338f2.png)

For the first iteration, the desire outcome is to send emails that follows a basic structure of the previous example.

## Context

We got a [request from LLVM](https://github.com/github/devrel/issues/874) where they ask to be able to subscribe/filter notifications by labels because they are overwhelmed by all the notifications they receive with the existing subscription capabilities of Newsies. The problem has been articulated by several customers in the past and we gathered [customer feedback](https://github.com/github/notifications/issues/864) to understand what notification scenarios are required. 

The current system (Newsies) is not architected to support these scenarios. The notification team did a research and came up with a prototype of a [Notification Platform](https://github.com/github/notifications_platform) that satisfies new requirements.

After the subscription system was built in Notifyd that will replace Newsies in the future and support flexible scenarios requested by customers. 
Once we have the end-to-end label subscriptions MVP working, and in order to enable the new label subscriptions feature, notifyd needs to deliver emails with an improved look and feel.

## Goals and objectives

- Provide solutions to support email templating in notifyd
- Provide solutions to integrate Primer and styles to a notifyd email

## Assumptions

- We don't need to build the full [Primer email layout](https://github.com/github/github/blob/master/app/views/mailers/layouts/primer_layout.html.erb) for this iteration, but check if we can build a solution for email templating for notifications being sent via notifyd.


## Guiding Principles

* Notifyd shouldn't incorporate domain logic of integrators.
* Integration solution should be as simple as possible.
* Templating solution should be easy to maintain and extend.
