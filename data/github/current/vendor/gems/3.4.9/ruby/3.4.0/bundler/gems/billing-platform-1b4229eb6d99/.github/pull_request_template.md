### What are you trying to accomplish?

<!-- Provide a description of the changes, including any screenshots, videos, or graphs if applicable. Link to any related issues or projects here. -->

### What approach did you choose and why?

<!-- This section is a place for you to describe your thought process in making these changes. List any tradeoffs you made to take on or pay down tech debt. Identify any work you did to mitigate risk. Describe any alternative approaches you considered and why you discarded them. -->

### Anything you want to highlight for special attention from reviewers?

<!-- This is your chance to identify remaining risks and confess any uncertainties you may have about the correctness of the changes. Highlight anything on which you would like a second (or third) opinion. Keep in mind how much traffic will be affected by your changes when assessing risk. Check out https://thehub.github.com/engineering/products-and-services/dotcom/pr-risk-and-rollout-review/#evaluate-the-pr-for-the-level-of-risk-it-presents for more details on risk assessment. -->

### Deployment Plan

<!-- Common deployment risk mitigation strategies are listed below. Delete all those that don't apply. Describe your plans if they don't fit into any of these buckets. https://thehub.github.com/engineering/products-and-services/dotcom/pr-risk-and-rollout-review/#evaluate-the-pr-for-the-level-of-risk-it-presents details the expectations for rollout/rollback contingency planning. -->

* **Feature Flag** - Change can be disabled by feature flag, but will need to be rolled back if the feature flag does not work. Please link to the relevant feature flags below.
* **Rollback** - Change can only be disabled by rolling the train back, or by deploying a revert commit.

### Performance Impact

<!--
  If the changes in this pull request have an impact on performance, please describe them
  here. Otherwise, delete this comment and the "Performance Impact" header above.
-->

### Observability

<!--
  If you have observability resources for this change other than the deployment dashboard
  and sentry, please link them here, otherwise delete this comment and the "Observability" header above.
  Examples might include custom graphs, dashboards, or EXPLAIN statements.
-->
