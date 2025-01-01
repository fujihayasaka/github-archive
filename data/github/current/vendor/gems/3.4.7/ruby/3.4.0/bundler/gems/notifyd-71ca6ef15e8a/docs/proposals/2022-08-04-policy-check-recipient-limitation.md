# [Proposal] Policy check recipient limit removal

## Preface

Some definitions:

- AOR: Means "Area of Responsibility"
- Qualifying a recipient means checking that a possible recipient isn't a bad
  actor or has not otherwise explicited that they don't want to be notified
  about the activity of a given subject/actor.

## Brief

As explained [here][1] as part of the `notify` worker normal process we perform
a check to qualify any possible recipient as a definitive recipient. Those
checks include data from many different data sets that are not owned by
`notifyd` or accessible in any way outside of the monolith. 

This data includes:

- Information about the user status regarding platform health (spamminess
  considerations, user ignores/blocks, etc) that belongs to the Platform Health
  AOR.
- Information about the user itself and whether it is considered a `Bot` or an
  `Organization` by our codebase.
- Some legacy data from `newsies` that we still cross check as we had not found
  a proper way to check it from `notifyd`. This data will be handled by the
  subscription system from notifyd sooner rather than later.

This check is performed in batches of up to 250 possible recipients and just
fails for batches bigger than 250.

Unfortunately while adding new types of notifications and opening `notifyd`
more and more to GA we'll find recipient populations that are, for sure bigger
than 250.

An example of this is the recent incident where a team mention on the Epic
organization notified 400k users.

So far our strategy with these has consisted in:

- Performing authorization checks before policy checks with the hope that this
  reduces the size of the recipient set.
- Lifted the limitation from 100 to 250, which has mitigated the issue, but not
  fixed it in the long term.

Our goal with this proposal is to find a proper long term solution.

As an example in [this query][2] we can see processed messages whose number of
recipients exceeds 100. Luckily we yet to detect cases where we go beyond 250,
but they can still happen.

## The state of things

### The ideal world

Ideally `notifyd` would have a way to query this data from other services each
one owned and operated by the relevant AORs.

Then, when needed, `notifyd` would issue requests to the proper APIs, maybe in
form of RPCs, and that would tell us everything we would need to know about a
potential recipient to either qualify it as valid or not.

While things are far from here I'm describing this as our current solution is
in some form limited by the way we can access this data.

Unfortunately this is not an option right now. GitHub's architecture doesn't
support such a fine grained split of service responsibilities that would make
possible and we need a solution to this problem sooner rather than later.

In the context of this proposal when we refer to a **full featured SOA** we are
talking about an architecture where every AOR operates a set of services that
provides access to the data needed by other AORs and shortcuts like
`monolith-twirp` are not needed.

### Data denormalization and owning the data to simplify the problem

Other teams besides use face the same issue and work on solutions that could
allow data denormalization without such a fine grained SOA. The middle ground
and a first step towards that involves finding solutions for problems that are
generally hard in distributed systems and microservice architectures:
**Distributed writes and Change Data Capture**.

[This issue][3] on the data-pipelines repo explains the issue well and in
detail with examples from many teams.

To summarize it I'll focus on some points:

- The goal is to find a way to eventually transform GitHub's architecture into
  an **Event Driven Architecture** so that writes are transformed into events
  that different AORs can subscribe to in order to denormalize the data as they
  need.
- As a previous step it describes the `CDC` (Change Data Capture) mechanism
  that could help bootstrap this process. Some teams use [Maxwell][4] in order
  to achieve this.
- The associated problems to these patterns, like atomicity and
  transactionality are normally mentioned as big drawbacks of this solution.

In addition to the complexities associated, there are other problems that hit
our specific use case.

Taking for example the case of platform-health data (spamminess, etc.):

- We could get the data we needed from the monolith, but in order to
  denormalize it we would basically require a transition that iterates over all
  the users on the GH database, which is already reason enough to discard it.
- Keeping it up to date on the other hand would be possible by means of the
  `hydro.github_v1_abuse_classification` hydro topic. But it would still be
  costly and complex.
- Same cost applies for other data sets like `User` information, etc.

Given the number of drawbacks combined with the cost of achieving data
ownership the problem is big enough that we would rather make things more
complicated for us and it wouldn't help us mitigate the problem  we have with
data access in the long term.

## The proposed solution

Unfortunately the limitation on the endpoint exists for some reasons:

- The queries done on the endpoint are hard to batch as they get data from
  different tables and models.
- They include at least one N+1 when querying for platform health parameters as
  it can be seen in [this trace][5].

[We have since then mitigated][6] some of the problems with this endpoint by
removing some redundant queries and making it a bit easier to group operations
that could be batched.

This is however not enough and can still become a problem, given that and
taking into account our objectives I recommend that we follow this path:

1. Better measure the response time of this endpoint. Our current metrics are
   captured from the controller, which doesn't give us the time perceived from
   `notifyd`. In case it is possible try to include tracing in this step.
2. Remove the limitation from the endpoint and instead find a way to control it
   from `notifyd` side. This will give us flexibility to operate the endpoint
   and adapt it whenever needed as `notifyd` is much easier to modify and fix
   than the monolith.

   Other alternative is to keep the limitation on the endpoint but also allow
   the caller (`notifyd`) to establish new limits.
3. Group and parallelize requests that are beyond the limit we stablish. This
   means that if we decide requests can only process 100 recipients, any
   population of more than 100 recipients is processed in groups of parallel
   requests of up to 100.
4. Find a way to eliminate the N+1s that currently affect us when checking
   recipient ignores and blocks.
5. Reevaluate our SLOs for cases with many recipients and consider creating low
   queues to process them.

   This implies a new set of workers separated from the initial one that only
   serves requests that are known to be slow (e.g. more than 1000 recipients)
   and also either removing such messages from our current SLOs or finding new
   SLOs for them.

This plan can be split in 2 main parts:

- Improving how we access and what is done on the qualifying endpoint (parts 1,
  2, 3 and 4)
- Finding a way that allows us to split big populations into smaller chunks
  that could be easily solved.

As described before, we are somewhat limited in the way we can access data, so,
while we can try some improvements there, the main problem is that big batches
of recipients are impossible to handle in our current architecture. In addition
the problem with the recipient population could still grow too much (ditto
Epic).

### Splitting big recipient populations

Qualifying recipients is the responsibility for the first worker on our
pipeline. This includes:

1. Matching the activity with a set of subscribers.
2. Checking authorization for all of them on `authzd`
3. Checking qualification checks on the `monolith-twirp` endpoint.
4. Matching them with the right channels.

Once that is done, each recipient is dispatched to the next step in the
pipeline, that performs the delivery.

In order to reduce the problem with the population size we can just divide an
conquer it.

After `1.` We know what could be the total population in the worst case, so
this is the place where we should split the problem.

### What others do

One of the service we use to qualify recipients is `authzd`. Among its options,
`authzd` includes one that allows to [slice batched requests][7]. This helps
splitting the load among the service fleet. This doesn't parallelize the
requests, but splitting the load among the service fleet is still a nice
recommendation.

Our current batch check against monolith-twirp could perform in a similar way
and it could also parallelize the requests. This would help us keep load even
among requests but also keep our latency on track in terms of SLOs.

### The missing part on our architecture: Slow queues.

This has been commented already in the past. `notifyd` is currently serving in
a 1 size fits all model for our SLOs and while that has worked OK for now it is
not going to scale infinitely.

Our current is composed of:

1. Notify msg (calculates subscribers, qualifies recipients, enqueues delivers)
2. Deliver push and emails

With this change we would have

1. Notify (calculates subscribers)
2. Qualify (qualifies recipients, enqueues delivers)
3. Deliver push and emails

Most of the times, going from 1 to 2 would be a 1-1 operation. One `Notify`
message would mean one `Qualify` message.

In cases where the calculated population of subscribers is bigger than some
limit, we should then split into many `Qualify` messages that would in time be
processed by a "slow" queue instead.

In this case, "slow" means that the queue would have more flexible SLO, workers
are meant to consume similar resources.

## Fixing the data problem beyond `notifyd`

While the chosen option will give us space and time, it is not enough. It will
eventually become a problem and it is only a matter of time that we find a new
check that needs to be added making the problem worse in some other way.

This doesn't only affect us but the whole GitHub and it requires scoping a
solution that goes beyond our own objectives as a team.

I propose that in addition to this short-term solution we help the rest of the
organization with scoping, understanding and funding the solution to this
problem by:

1. Advocating for a SOA when possible and helping other teams by sharing more
   of our experiences getting decoupled from the monolith.
2. Getting involved when possible in the initiatives that help us achieve that
   state of our architecture.

[1]: https://github.com/github/notifyd/issues/543
[2]: https://splunk.githubapp.com/en-GB/app/gh_reference_app/search?q=search%20index%3Dnotifyd%20kube_namespace%3Dnotifyd-production%20cmd%3Dnotify-worker%20authorized_recipients_count%20%3E%20100%20%7C%20table%20authorized_recipients_count&display.page.search.mode=verbose&dispatch.sample_ratio=1&earliest=-7d%40h&latest=now&display.prefs.events.count=50&display.prefs.statistics.offset=0&sid=1659620654.293422_5FB4AC8E-DC1F-4236-99DC-C6032DC30760&display.page.search.tab=statistics&display.general.type=statistics
[3]: https://github.com/github/data-pipelines/issues/1196
[4]: https://maxwells-daemon.io/
[5]: https://app.lightstep.com/s/trace/B_ia4cR1dqiF
[6]: https://github.com/github/github/pull/230474
[7]: https://github.com/github/authzd/tree/master/pkg/client#splitting-batchauthorize-requests-into-slices
