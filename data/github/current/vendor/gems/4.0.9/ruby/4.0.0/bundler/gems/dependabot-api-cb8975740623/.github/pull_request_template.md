### What are you trying to accomplish?

<!-- Provide both a what and a _why_ for the change. -->

<!-- What issues does this affect or fix? -->

### Anything you want to highlight for special attention from reviewers?

<!-- If there were multiple ways to approach the problem, why did you pick this one? -->

#### Which environments does this change target?

<!-- Select all that apply. If this is a Production change that excludes dotcom, proxima or GHES,
     please explain why this change does not apply to those environments. -->

- [x] Production
  - [x] dotcom
  - [x] proxima
  - [x] GHES
- [ ] Non-production
  - [ ] dsp-testing
  - [ ] docs

#### Risk Assessment

  <!-- Are we introducing any new calls to dotcom? Any writes that could happen on that side? How do we expect that to impact the load on any database clusters? -->

- [ ] **Low risk** the change is fully under one or more Feature Flags OR the modifications are small, highly observable, and easily rolled back.
- [ ] **Medium risk** changes that are isolated, reduced in scope or could impact few users and not bring the site down.
- [ ] **High risk** changes are those that could impact our customers and SLOs, low or no test coverage, low observability, or slow to rollback.

### Is there a Feature Flag?

- [ ] **Yes** - Change can be disabled by feature flag, but will need to be rolled back if the feature flag does not work. Please document the feature flag name(s) below.
- [ ] **No** - Change can only be disabled by rolling back via the merge group, or by deploying a revert commit.

<!-- Document the feature flag name(s) here. If this is a production change and it does _not_ have a Feature Flag, briefly explain why here. -->

### How will you know you've accomplished your goal?

<!--
  * Should any particular metrics/dashboards be monitored for observability?
  * If you've reproduced an error, can you link to the reproduction?
-->
