<!--
Provide context and explain why this pull request exists. Include screenshots, query analytics, and graphs here, if you have any.

Code changes should be in response to an issue. If one does not already exist, create one in the relevant repository.
Link related discussions, comments, pull requests, and feature releases (see https://github.com/github/releases#readme).
-->

### Which changes are being made in this PR?
<!-- Describe your changes and what you want to achieve in this PR -->


### Which clients does this change target?
<!--
Changes to Authnd will have an impact to our clients, knowing the affected clients will help to evaluate the risk of the change.
Find affected clients based on the top list of clients in this Datadog Dashboard: https://app.datadoghq.com/dashboard/nu7-a4k-jza?fullscreen_widget=4032805540489748&live=true

Please check all that apply.
-->

- [ ] Dotcom
- [ ] Moda Services (Copilot API, github-models, api-gateway, goproxy etc) <!-- please list the services -->
- [ ] Other: <!-- please specify -->

### How did you validate the changes in this PR?

<!-- Describe how you are validating the changes in your PR -->

### Rollout Plan and Rollback Strategy

<!--
Describe how you plan to rollout this change and what the risks are.

Here are some prompts to think about in regards of rollout:
- Could your changes be picked up by a client prematurely?
- Which Feature Flags are protecting the changes here?
- How are you going to onboard your client to the changes in this PR?

-->
- **Other** - Describe your plans if they don't fit into any other buckets.
- **Experiment** - Change will be tested with an experiment, but will need to be rolled back if the experiment does not work. Please link to the relevant experiment below.
- **Feature Flag** - Change can be disabled by feature flag either in Authnd or in the client, but will need to be rolled back if the feature flag does not work. Please link to the feature flag.
- **Rollback** - Change can only be disabled by [rolling back](https://github.com/github/ops/blob/master/docs/playbooks/authnd/deployment.md) the merge group, or by deploying a revert commit.

### Risk Assessment

<!--
Choose one of the following and detail why this level was chosen. Delete the others.

See also: https://thehub.github.com/engineering/products-and-services/dotcom/pr-risk-and-rollout-review/#evaluate-the-pr-for-the-level-of-risk-it-presents
-->

- **Low risk** the change is fully under one or more Feature Flags (client or Authnd), evaluated by an experiment, or the modifications are small and highly observable.
- **Medium risk** changes that are isolated, reduced in scope or could impact few users and not bring the site down.
- **High risk** changes are those that could impact our customers and SLOs, low or no test coverage, or low observability.
