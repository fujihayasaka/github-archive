# Brief: Database Improvements

## Problem Statement

Currently `notifyd` uses a very basic connection pattern to talk to the
database that doesn't allow for throttling writes or reading from
read-replicas. In addition while we have Vitess generally set up, we don't yet
use any sharding.


## Context

### Read replicas
The current implementation of database access in `notifyd` is very direct.
Which means we open a connection to the database via a specific DSN and use
that same connection everywhere. This basically means we have a single
"database host"[^1] that we use for all DB interactions. And that setup
currently doesn't support any notion of roles like we have in the monolith
where we can explicitly connect to a read replica for a block of code:


```ruby
ApplicationRecord::Mysql1.connected_to(role: :reading) do
  # code here connects to replica
end
```

Or even set different databases for reading and writing [for the whole
application
record](https://github.com/github/github/blob/1c98acb230fc6f8c8865f09a52dbe77211fd798b/lib/application_record/notifications_deliveries.rb#L7):

```ruby
connects_to database: { writing: :notifications_deliveries_primary, reading: :notifications_deliveries_readonly }
```

**Challenges:**

The challenges for implementing this are two-fold. First of we need to design
an API around how to expose this to client code. The actual change of the
connection is as easy as appending `@replica` to the keyspace in the DSN. So
for example:

```
notifyd_rw_0:secret-password@tcp(vtgate-mysql-notifyd-production.service.iad.github.net:10066)/notifyd_ks"
```

becomes

```
notifyd_rw_0:secret-password@tcp(vtgate-mysql-notifyd-production.service.iad.github.net:10066)/notifyd_ks@replica"
```

As a next step we need to then figure out how to decide which code parts can
actually read from replicas and are resilient to potentially stale reads.



### Write throttling

Our current way of connecting to databases also doesn't provide any way to
throttle writes if need be. The default way to do this at GitHub is
[Freno][freno] and we have libraries ready to go for this for golang. In the
monolith we most often interact with Freno via so-called [throttler
objects](https://github.com/github/freno-client#throttler-objects) like this
example

```ruby
store = NotificationDeliveryStore.new(delivery.list, delivery.thread, delivery.comment)
NotificationDelivery.throttle { store.save(unsaved_deliveries.transform_keys(&:to_i)) }
```

from the [deliver notifications
job](https://github.com/github/github/blob/1c98acb230fc6f8c8865f09a52dbe77211fd798b/app/jobs/newsies/deliver_notifications_job.rb#L387-L394).

This becomes very important as we start tracking deliveries from consumers in
the database to prevent double deliveries. We will have a large uptick in
database writes then that need to support throttling to not overwhelm the
database.

**Challenges:**

Here we also have 2 main challenges to implement support for throttling. We
need to integrate the [official freno
client](https://github.com/github/go-freno-client) and expose a throttling API
to be used from `notifyd` code. We then also need to decide which parts of
`notifyd` can tolerate being throttled. In general throttling is only supposed
to be used in async paths (i.e. not in web requests) so the consumers should
be audited for this and the twirp API is going to be out of scope.


### Sharding (out of scope)

With sharding we can make sure we balance out the data that would usually be
in a single table or database to be spread out across various different
database shards. This is all handled by the Vitess layer which we already have
set up for `notifyd`. Once we want to start sharding we can enable that
transparently in Vitess and don't need to make any changes to

**Challenges:**

The challenge here is to know when to enable sharding. So we need to come up
with a plan as to when it actually makes sense and up to which point it's
additional unneeded complexity and waste of resources. So we need to define
metrics that tell us in advance when we should start sharding.

**Out of scope reasons:**

After talking to the database team about this we decided it doesn't really
make sense to focus on this right now. Sharding early on is fairly expensive
given the hardware cost and added complexity. And we don't even know yet
whether and when we really need it. The metrics to decide if we should start
sharding are basically replication lag and disk space (i.e. if we end up with
one very big table). So we won't consider enable sharding for now until we 
see signs of operational pressure to do so

### Goal

- have a way to automatically throttle writes if necessary and implemented
- provide an easy to use way to denote read-only/replica connections in code
- determine a path forward when and how to enable sharding in vitess layer



[^1]: It's not actually a single host because we have various layers of GLB,
  ProxySQL, vitess, etc in front of the actual database host
[freno]: https://github.com/github/freno
