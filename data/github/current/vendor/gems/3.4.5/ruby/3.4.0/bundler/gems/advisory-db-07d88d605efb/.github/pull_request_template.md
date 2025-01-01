<!--
Provide context and explain why this pull request exists. Include screenshots, videos, and graphs here, if you have any.

Code changes should be in response to an issue. If one does not already exist, create one in the relevant repository.
Link related discussions, comments, pull requests, and feature releases (see https://github.com/github/releases#readme).
Format links with a Markdown list so that each title unfurls automatically, e.g.,
- Closes <issue URL>
- Feature flag <issue or devportal URL> -- create a rollout issue via https://github.com/github/github/issues/new?template=feature_flag_rollout.md&title=%5BFF%5D+
- Based on <preceding pull request URL>
-->

### What approach did you choose and why?

<!--
Describe the changes and your thought process in making them. For example:

- Tradeoffs: List tradeoffs you made to take on or pay down tech debt.
- Risk: Identify work done to mitigate risk.
- Alternatives: Describe alternative approaches you considered and why you discarded them.
- Attention: Anything you want to highlight for special attention from reviewers.
- Observability: List ways to monitor this change besides the deployment dashboard and Sentry.
- Accessibility: Explain any new violations, disabled linters, or improvements to accessibility.
-->
### Risk Assessment

<!--
Choose one of the following and detail why this level was chosen. Delete the others.

See also: https://thehub.github.com/engineering/products-and-services/dotcom/pr-risk-and-rollout-review/#evaluate-the-pr-for-the-level-of-risk-it-presents
-->

- **Low risk** changes are fully under feature flag(s) OR the changes are small, highly observable, and easily rolled back.
- **Medium risk** changes that are isolated, reduced in scope or could impact few users and not bring the site down.
- **High risk** changes are those that could impact our customers and SLOs, low or no test coverage, low observability, or slow to rollback.

### If something goes wrong, what are the mitigation and rollback strategies?

<!-- Delete risk mitigation strategies that don't apply. See also: https://thehub.github.com/engineering/products-and-services/dotcom/pr-risk-and-rollout-review/#evaluate-the-pr-for-the-level-of-risk-it-presents -->

- ### **Unknown** - **I forgot to update this section and don't have a mitigation strategy.**
- **Other** - Describe your plans if they don't fit into any other buckets.
- **Experiment** - Change will be tested with an experiment, but will need to be rolled back if the experiment does not work. Please link to the relevant experiment below.
- **Solo Deploy** - This change will be deployed solo, making it easier to monitor impact and revert if necessary. Solo deploys should be used sparingly since they prevent others from shipping with you.
- **Feature Flag** - Change can be disabled by feature flag, but will need to be rolled back if the feature flag does not work. Please link to the feature flag in the DevPortal. <!-- Most production changes should be protected by feature flag(s). -->
* **Staging Deploy** - This change will be tested on the staging environment before being queued to deploy (this can only be done with inbox today).
- **Rollback** - Change can only be disabled by [rolling back](https://ops.githubapp.com/docs/playbooks/github_deployments.md) the merge group, or by deploying a revert commit.

---

<!-- Authors: Please fill out this form carefully and completely. See also https://github.com/github/advisory-db/blob/main/README.md#deployment -->

_**Reviewers:** Please read carefully. By approving, you support the deployment and mitigation plans as well as the code change. If anything is unclear or missing, please ask for updates._
