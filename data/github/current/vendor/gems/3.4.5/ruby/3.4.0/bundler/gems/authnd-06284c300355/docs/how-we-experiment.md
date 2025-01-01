# How we Experiment

This document describes the basis for, tools, and methods, for rolling out experimental usage of `authnd` for GitAuth.

## Background

A core goal of this work is to reduce operational dependency on gh/gh.
As we roll this work out, we need to be very careful, and understand the impact of our work.
We are working on an important piece of GitHub's architecture where we'll swap out old gh/gh internal Authn mechanisms with `authnd` usage.
At each stage we must understand the types of change and risk we're incurring by incorporating this new service.
With this document we're aiming to agree on and move forward with a specific set of tools to help understand:

1. How to measure/observe what we're replacing (gh/gh authn usage)
1. How to measure/observe what we're targetting (authnd service usage)
1. How to safely roll this out to staff or a specifically reduced set of users while we test/learn

## Tools

* [Datadog](https://app.datadoghq.com/dashboard/nu7-a4k-jza)
* [Sentry](https://sentry.io/organizations/github/issues/?project=5391058)
* [Scientist](https://github.com/github/scientist)

## Observability

We're using Scientist to basically dark-ship our incorporation of `authnd` into the GitAuth request handler flow.
With careful exception handling, circuit breaking, proper timeout configuration
we should be able to get a basic understanding of the performance and reliability impact of using `authnd` within GitAuth.

Using our dashboards we should compare today's results with the results of `authnd` usage for both accuracy and performance.
This should directly influence whether we can proceed with the system as designed, measure success.

## Rollout

In this area of the service it's extremely important that we maintain a high opertaional bar.
To that end, we need to be very methodical in how we rollout. Some notes and guidelines:

1. For github/github
   - Use [staging](https://githubber.com/article/technology/dotcom/deploy/staging-labs) for pre-prod experimentation
   - Use Garage for some closer-to-production testing
   - Review-lab is too ephemeral to have SSH connections which makes it not-very-useful for a lot of our test cases
   - [More info on environments at GitHub](https://githubber.com/article/technology/dotcom/deploy/environments.md)
1. `authnd` has no pre-production environment
1. If you're shipping it, you've seen aspects of the flow work in a development environment, and pre-production environment when possible
1. If you're shipping it, you're around to see that it works in production without interruption
1. For GitAuth Experimentation it should first be shipped with 0% usage of the experiment, then rolled out internally, before ever testing
  more broadly

For the purposes of this phase (Wall-E) of `authnd` we're likely to only get to the "internal" rollout.
Since these requests are coming in before authentication or authorization is done, it's not as simple as usual to limit requests to staff.
For unique cases we should document how we limited use of `authnd` experimentation.
For the immediate term, our options to limit usage are:

1. Provide a set of IPs we provide or an IP range that fits within the Developer VPN that whitelists when the experiment is used
1. Limit to a set of users/orgs/repos by path
   - This is not possible for `verify-key`, we don't have this information
1. We could store a list of our key fingerprints, store these in vault, hydrate a list at service boot and use these to whitelist when the
  experiment is used

## Pull Requests

Pull Requests that affect live usage of GitAuth should clearly state the effects expected.
They should also provide clear example of original and expected performance, correctness through the use of something like scientist when possible. 

## Flagging/rollout

Our experimentation work is wrapped in multiple pieces of protection:

1. Feature Flag
1. Science Experiment
1. Client timeout configuration
1. Ruby timeout around the experimental code

The Feature Flag and Science Experiment are our main controls for rollout that don't require code changes.

The Feature Flag, [`authnd_experiment`](https://admin.github.com/devtools/feature_flags/authnd_experiment), allows us to control rollout in a few ways:

1. Stable Percent of calls (percent based on input)
1. Random Percent of calls (percent based on number of calls)
1. Server Role
1. Server Hostname
1. Fully enabled

For our purposes we don't really care about Stable percent of calls.
Random percent, specific server Roles, Hostnames or fully on are what we care about.
Server Role/Hostname are more for usage inside of Garage in particular.
This is because in production, hostname is unstable due to gitauth being deployed in kubernetes.
Role is checked, but only really gives us another avenue of control if we need to be picky about how we enable per-environment.
On production, Role is basically one which appears to be something like `unicorn-gitauth-api`.

[Science Expirements](https://devtools.githubapp.com/experiments) can also be rolled out on a percentage basis.
Our experiments start with `authnd.`.

In practice, we need to care about both the feature flag, as well as the science experiment when thinking about rollout.
We could combine percentage configurations to rollout to less than `1%` of calls, or for simplicity we can fully enable the feature on production, with a low percentage rollout on the experiment.
Before we get into that math, it should be called out that Feature Flags' random percent configuration is computed by how many times `enabled?` is called.
At the time of writing this, the code calls `enabled?` on that feature _twice_ to check if it's enabled for the server _role_ then check the _host_.
This means that the number of times we call `enabled?` in production depends on if the first `enabled?` returns true.
In most cases on production-proper, with the current configuration that targets very little or none of public production traffic it will call `enabled?` twice in the codepath.
So, with that information, if we enable 1% of traffic using the feature flag, it's likely closer to `2%` of traffic will get past that gate.

Next, we need to take into account percentages of the experiment.
If we wind up with `2%` of traffic getting into the experiment, with a `1%` limit on the experiment, we're only testing `1%` of `2%` of all traffic.
That means if we have `10000` requests over 1 minute, we can assume we'll get `.01*.02*10000` requests; or 2 requests per minute.
This percentage of percentages detail can work in our favor for controlling the impact we have on day one, but we also have to be frank and aware of its effects.
