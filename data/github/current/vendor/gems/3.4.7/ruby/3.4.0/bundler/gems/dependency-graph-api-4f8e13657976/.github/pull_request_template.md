<!-- Authors: Please fill out this form carefully and completely. See also https://thehub.github.com/engineering/development-and-ops/deployment/deploying-dotcom/ -->

_**Reviewers:** Please read carefully. By approving, you support the deployment and mitigation plans as well as the code change. If anything is unclear or missing, please ask for updates._

### Context

<!--
This section ties together context explaining why this pull request exists.

Code changes should be in response to an issue. If one does not already exist, create one in the relevant repository.
Link related discussions, comments, pull requests, and feature releases (see https://github.com/github/releases#readme).
Format links with a Markdown list so that each title unfurls automatically, e.g.,
- Closes <issue URL>
- Based on <preceding pull request URL>
- Part of <feature release URL>
-->

### What are you trying to accomplish?

<!-- Describe the changes. Include screenshots, videos, and graphs here, if you have any. -->

### What approach did you choose and why?

<!--
This section is a place for you to describe your thought process in making these changes. For example:

- Tradeoffs: List tradeoffs you made to take on or pay down tech debt.
- Risk: Identify work done to mitigate risk.
- Alternatives: Describe alternative approaches you considered and why you discarded them.
- Attention: Anything you want to highlight for special attention from reviewers.
- Observability: List ways to monitor this change besides the deployment dashboard and Sentry.
- Accessibility: Explain any new violations, disabled linters, or improvements to accessibility.
-->

### Which environments does this change target?

<!--
Which environments does this change impact? Select those that apply.

If it's a Production change and you deselected any Production environments, explain why this change does not apply to those environments.
-->

- [x] Production: dotcom
- [x] Production: proxima
- [x] Production: GHES
- [ ] Non-production: dev/test

### Risk Assessment

<!--
Choose one of the following and detail why this level was chosen. Delete the others.

See also: https://thehub.github.com/engineering/products-and-services/dotcom/pr-risk-and-rollout-review/#evaluate-the-pr-for-the-level-of-risk-it-presents
-->

- **Low risk** the change is fully under one or more Feature Flags OR the modifications are small, highly observable, and easily rolled back.
- **Medium risk** changes that are isolated, reduced in scope or could impact few users and not bring the site down.
- **High risk** changes are those that could impact our customers and SLOs, low or no test coverage, low observability, or slow to rollback.

### Feature Flags

<!--
Most production changes should be protected by one or more Feature Flags. Please link Feature Flag Rollout issues (see https://github.com/github/github/issues/new?template=feature_flag_rollout.md&title=%5BFF%5D+ to create one).

Production change without a Feature Flag? Explain why. For non-production changes, comment "N/A".
-->

### If something goes wrong, what are the mitigation and rollback strategies?

<!-- Delete risk mitigation strategies that don't apply. See also: https://thehub.github.com/engineering/products-and-services/dotcom/pr-risk-and-rollout-review/#evaluate-the-pr-for-the-level-of-risk-it-presents -->

- ### **Unknown** - **I forgot to update this section and don't have a mitigation strategy.**
- **Other** - Describe your plans if they don't fit into any other buckets.
- **Experiment** - Change will be tested with an experiment, but will need to be rolled back if the experiment does not work. Please link to the relevant experiment below.
- **Solo Deploy** - This change will be deployed solo, making it easier to monitor impact and revert if necessary. Solo deploys should be used sparingly since they prevent others from shipping with you.
- **Feature Flag** - Change can be disabled by feature flag, but will need to be rolled back if the feature flag does not work. Please link to the feature flag in the DevPortal.
- **Review Lab Deploy** - This change will be tested on review-lab before being queued to deploy.
- **Rollback** - Change can only be disabled by [rolling back](https://ops.githubapp.com/docs/playbooks/github_deployments.md) the merge group, or by deploying a revert commit.
