_Reviewers: By approving this Pull Request you are approving the code change, as well as its deployment and mitigation plans._

_Please read this description carefully. If you feel there is anything unclear or missing, please ask for updates._

### What are you trying to accomplish?

<!-- Provide a description of the changes, including any screenshots, videos, or graphs if applicable. Link to any related issues or projects here. Why are you making these changes? -->

#### List the issues that this change affects.

<!--Please link any code change to any corresponding issue(s). If one does not already exist and the pull request is a sizable change (e.g. bug fix, completes a task), please create one.  Otherwise specify N/A. -->

#### Risk Assessment

<!-- Please select from one of the following and detail why this level was chosen -->
<!-- Check out https://thehub.github.com/engineering/products-and-services/dotcom/pr-risk-and-rollout-review/#evaluate-the-pr-for-the-level-of-risk-it-presents for more details on risk assessment. -->

- [ ] **Low risk** the change is fully under one or more Feature Flags OR the modifications are small, highly observable, and easily rolled back.
- [ ] **Medium risk** changes that are isolated, reduced in scope or could impact few users and not bring the site down.
- [ ] **High risk** changes are those that could impact our customers and SLOs, low or no test coverage, low observability, or slow to rollback.

### What approach did you choose and why?

<!-- This section is a place for you to describe your thought process in making these changes. List any tradeoffs you made to take on or pay down tech debt. Identify any work you did to mitigate risk.
Describe any alternative approaches you considered and why you discarded them. -->

### Anything you want to highlight for special attention from reviewers?
<!-- This is your chance to identify remaining risks and confess any uncertainties you may have about the correctness of the changes. Highlight anything on which you would like a second (or third) opinion. Keep in mind how much traffic will be affected by your changes when assessing risk. -->

### Feature Flags

<!-- Most production changes should be protected by one or more Feature Flags. Please link the Feature Flag Rollout issues for each Feature Flag below. (TBD) If you need to create a Feature Flag Rollout issue, follow this link: https://github.com/github/github/issues/new?template=feature_flag_rollout.md&title=%5BFF%5D+. -->

<!-- If this is a production change and it _does not_ have a Feature Flag, briefly explain why here. -->

<!-- If this is a non-production changes simply enter N/A. -->

### If something goes wrong, what are the mitigation and rollback strategies?

<!-- Common deployment risk mitigation strategies are listed below. Delete all those that don't apply. Describe your plans if they don't fit into any of these buckets. https://thehub.github.com/engineering/products-and-services/dotcom/pr-risk-and-rollout-review/#evaluate-the-pr-for-the-level-of-risk-it-presents details the expectations for rollout/rollback contingency planning. -->

- ### **Unknown** - **I forgot to update this section and don't have a mitigation strategy.**

* **Experiment** - Change will be tested with an experiment, but will need to be rolled back if the experiment does not work. Please link to the relevant experiment below.
- **Solo Deploy** - This change will be deployed solo, making it easier to monitor impact and revert if necessary. Solo deploys should be used sparingly since they prevent others from shipping with you.
- **Feature Flag** - Change can be disabled by feature flag, but will need to be rolled back if the feature flag does not work. Please link to the relevant feature flags below.
- **Review Lab Deploy** - This change will be tested on review-lab before being queued to deploy.
- **Rollback** - Change can only be disabled by [rolling back](https://ops.githubapp.com/docs/playbooks/github_deployments.md) the merge group, or by deploying a revert commit.

### How did you test these changes?
<!-- Did you run/add unit tests? Feel free to note just that.-->

### Does this change need to be back-ported to current and previous GHAE/GHES releases?

### Observability

<!--
  If there are any new metrics or log statements, please ensure that they conform with the
  [GitHub Telemetry Go User Guide](https://thehub.github.com/epd/engineering/dev-practicals/observability/logging/github-telemetry-go-user-guide/).
  This means using separate fields rather than string interpolation and following [Semantic Conventions](https://thehub.github.com/epd/engineering/dev-practicals/observability/logging/github-telemetry-go-user-guide/#replacing-keys-with-semantic-conventions) for the names of those fields.

  If you have observability resources for this change other than the deployment dashboard
  and sentry, please link them here, otherwise delete this comment and the "Observability" header above.
  Examples might include custom graphs, dashboards, or EXPLAIN statements.
-->
