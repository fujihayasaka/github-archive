/*
Package newsiesservice implements the watch/unwatch/ignore flows from newsies using the notifyd primitives. Since
the primitives from notifyd are mostly low level and pretty far away from the ones in newsies, we
decided to use this service to build an abstracton that is easier to understand and that allows us
to easily build the existing flows in order to migrate.

The flows are:

  - Watch: subscribe to all the activity on a repository or to all the activity on a given set of
    thread types (e.g. only issues and PRs). Also cleanup existing ignores.
  - Unwatch remove existing subscription and be notified only about things in which I'm
    participating, like when I'm mentioned, I'm assigned, etc. Also cleanup existing ignores.
  - Ignore all activity on the repository and cleanup existing subscriptions.

We intentionally made the trade-off here to increase the level of abstraction in favor of velocity
even when we know that it couples us a bit to newsies.

In the future we will explore this path with a better abstraction that isn't newsies centric.
*/
package newsiesservice
