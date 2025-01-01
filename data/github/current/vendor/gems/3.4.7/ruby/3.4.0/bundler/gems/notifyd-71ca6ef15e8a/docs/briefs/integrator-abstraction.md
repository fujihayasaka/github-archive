# Brief: Interface for integrators

## Problem statement
We want to provide an easy to use interface to send notifications for all
product teams at GitHub regardless of which product they own. The interface
should not expose too many details about the implementation details of
`notifyd` but still give the flexibility to customise the notification
experience as needed by the product.

This interface isn't a single thing but multiple touchpoints with the notifyd
platform:

- The `Notify` hydro message
- Layouts for different channels
- The individual subject adapters for events
- The twirp API to manage subscriptions
- Analytics on delivered notifictations
- Channel definitions (e.g. email, mobile push, etc)
- Documentation for integrating with the platform

We currently have a big source on uncertainty here as to which level of
abstraction is useful and what kind of things we want to expose to the
integrators. If we get too close to the implementation of `notifyd` we make it
harder to change the platform and require integrators to learn about too many
`notifyd` concepts. If we get too abstract we run into the risk of not being
able to support details that need to be supported by notification platforms
(e.g. specific email headers for filtering, mobile push specific actions).

This ties directly into our [first fundamental requirement](https://github.com/github/notifyd/blob/main/docs/fundamental-requirements.md#1-integration-simplicity) for `notifyd`.

### Details

While we aren't yet in a position to define the complete integration surface
due to changes in flight and the overall complexity, the following are some
details to add some context to individual touchpoints of the platform.

**`Notify` hydro message**

The `Notify` hydro message is the sole communication layer for sending
notifications. The problem here lies with the decision we have to make of what
information goes into the message and how to encapsulate it. We generally
don't want to be too tied to the platform but still expose its flexibility to
integrators.

**Subject adapters**

The current abstraction layer for integrators to notifyd is encapsulated in
[`Notifyd::SubjectAdapter`](https://github.com/github/github/blob/master/app/models/notifyd/subject_adapter.rb)
in the monolith. The interface methods of the class map to a certain extent to
fields of the [`notifyd.v0.Notify` protobuf
message](https://github.com/github/hydro-schemas/blob/main/proto/hydro/schemas/notifyd/v0/notify.proto),
however not necessarily directly. This means currently subject adapters are
very tied to the message format and there is a lot of knowledge needed to
integrate it. So any decision on the message format impacts subject adapters
very directly.


**Channel specific layouts**

The most direct tie between the implementation details of `notifyd` currently
is exhibited by the layout methods (`def mobile_layout`, `def email_layout`)
which map fairly directly to the "body" of the notification but also for e.g.
the email layout to email headers we send. As an example, the current email
headers are used as follows:

- `From`: GitHub gives the components to notifyd and notifyd builds it
- `To`: GitHub gives the entire field to notifyd
- `Headers`: GitHub gives some fields to notifyd while others such as CC built are built entirely in notifyd

In addition there is an import email specific detail here which is the design
of email templates. We want integrators to be able to create and use their own
templates in the future. Which needs to have a properly designed process and
flow how to get those into notifyd, complete with testing cycles.


**The twirp API to manage subscriptions and settings**

From `notifyd` we expose a twirp API to interact with subscription data. This
mostly means storing subscritions that the user (or an automated flow in the
monolith) creates and retrieving them again for display and edit.
Here we want to find a trade off between not exposing too much of the data
model directly while giving the flexibility to manage subscriptions.
Soon we're going to introduce API to manage notification settings and will face the same challenges as with the subscriptions.

**Analytics on delivered notifications**
Integrators need to have a way to understand how their notifications are
doing. This goes beyond just understanding when sending fails but also for
example how many notifications actually end up at users versus getting blocked
in the platform due to e.g. settings.


**Channel definitions (e.g. email, mobile push, etc)**

Currently we support for the most part 2 channels (email and mobile push).
These channels are already very different and have different requirements for
data provided by the integrator. But they all initially flow through the same
`Notify` message format. We might add additional channels in the future and
need to provide a way to integrate with new channels as seamlessly as with the
existing ones.

Channels themselves also come with their own fine grained definition parameters
that we don't necessarily expose explicitly in all cases. We currently don't expose
all of them to integrators but that might change in the future. Some examples are
the previously mentioned email headers or specific parameters of the mobile push payload.


**Documentation for integrating with the platform**

Last but not least there is also the challenge of documenting the platform in
a way that makes it easy to use it without having to tightly pair with the
notification team to understand how integration with `notifyd` happens.






