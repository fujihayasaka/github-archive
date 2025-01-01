# 1. SSH Key Bookkeeping

Date: 2020-11-16

## Status

Approved

## Context

Currently the authnd service is set up to handle SSH requests in experiment along side the original gitauth flow. Before we reach the development stage and confidence to rely soley on the authnd service for SSH key validation, we will need to make sure that the authnd SSH key flow includes the same bookkeeping as the original. This generally refers to telemetry, audit logs, metrics and updating the mysql1 public_keys table to keep an accurate usage history (accessed_at) while it continues to be the source of truth.

In our investigation we've found that the user facing audit logs feature doesn't track SSH key authentication, since it would be an overwhelming amount of events for a person to parse through. We've found that only the public_key.access event is used and that it is already accounted for as part of both flows being run for the experiment (meaning that accessed_at is already being updated under the authnd half of the experiment). Gitauth contains the flow which runs the experiment and original paths for authenticating with SSH. There's a switch statement in gitauth with runs the authentication and then runs the authorization. The authorization is actually where most of the bookkeeping happens. This is where the accessed_at field is updated and some logs are emitted. There's only one log (metric) that happens as part of the authentication.

The one missing metric from the original flow is:

``` (Ruby)
      tags = ["type:pubkey"]
      tags << "member_type:#{pubkey.type}" if pubkey
      tags << "result:#{result}"
      GitHub.dogstats.increment("gitauth.verify_key", tags: tags)
```

All other bookkeeping is handled by authz and can be seen in this code block:

```(Ruby)
    def perform_bookkeeping
      unless public_key.nil?
        # Do some book-keeping to track that the key was used.
        PublicKey.access(id: public_key.id, last_accessed_at: public_key.accessed_at)
      end

      GitHub.dogstats.increment("git", tags: ["type:#{protocol}", "action:#{action}", "status:#{status}"])
      if status == :verified_email_required
        GitHub.dogstats.increment("git_access_blocked", tags: ["type:verified_email_required"])
      end
      if status == :ok && authorization&.maintainer?
        GitHub.dogstats.increment("git", tags: ["action:maintainer_pushed"])
      end
      if status == :ok && action == :write && public_key&.deploy_key?
        GitHub.dogstats.increment("git", tags: ["action:deploy_key_pushed"])
      end
    end
```

## Decision

Since the majority of bookkeeping is handled in authz we only need to add in the one missing metric into the authnd flow. This will be added in gitauth and needs to be logged after the call to authnd.

## Consequences

As a consequence of adding in the one missing metric, using authnd in experiment will have the same logs as using the original authn.
