<!--
Provide context and explain why this pull request exists. Include screenshots, videos, and graphs here, if you have any.

Code changes should be in response to an issue. If one does not already exist, create one in the relevant repository.
Link related discussions, comments, pull requests, and feature releases (see https://github.com/github/releases#readme).
Format links with a Markdown list so that each title unfurls automatically, e.g.,
- Closes <issue URL>
- Feature flag rollout issue -- create via https://github.com/github/github/issues/new?template=feature_flag_rollout.md&title=%5BFF%5D+
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

### Which environments does this change target?

<!--
Which environments does this change impact? Delete the ones that do not apply.

If it is a Schema Migration in `Production: dotcom`, also select `Production: proxima` as all schema migrations in dotcom automatically run in Proxima.
-->

- Production: dotcom <!-- (`environment:production-dotcom`) -->
- Non-production: dev/test only <!-- (`environment:non-production`) -->
- Non-production: docs <!-- (`environment:non-production`) -->

### Risk assessment

<!--
Choose one of the following and detail why this level was chosen. Delete the others.

See also: https://thehub.github.com/engineering/products-and-services/dotcom/pr-risk-and-rollout-review/#evaluate-the-pr-for-the-level-of-risk-it-presents
-->

- **Low risk:** Changes are fully under feature flag(s), or have been fully tested and validated in pre-production environments and are highly observable, or are documentation or test only. <!-- (`risk:low`) -->
- **High risk:** Changes are not fully under feature flag(s), have limited visibility and/or cannot be tested outside of production. <!-- (`risk:high`) -->

### How did/will you validate this change?

<!--
Introducing a regression that causes a rollback is disruptive to others and impacts our ability to quickly ship and iterate. To help mitigate that, please describe the steps you took to validate this change.
-->

- **Local server** - I ran `script/server` with these changes and executed the changed functionality. <!-- (`validate:script-server`) -->
- **Tests** - I am depending on test coverage. <!-- CI, Storybook, etc --> <!-- (`validate:tests`) -->
- **Other** - <!-- Please explain. --> <!-- (`validate:other`) -->
- **None** - I am not validating these changes. <!-- (`validate:none`) -->

### If something goes wrong, what are the mitigation and rollback strategies?

<!-- Delete risk mitigation strategies that don't apply. See also: https://thehub.github.com/engineering/products-and-services/dotcom/pr-risk-and-rollout-review/#evaluate-the-pr-for-the-level-of-risk-it-presents -->

- **Other** - <!--Describe your plans if they don't fit into any other buckets.--> <!-- (`mitigate:other`) -->
- **Experiment** - Change will be tested with an experiment, but will need to be rolled back if the experiment does not work. [add experiment link here] <!-- (`mitigate:experiment`) -->
- **Solo Deploy** - This change will be deployed solo, making it easier to monitor impact and revert if necessary. <!--Solo deploys should be used sparingly since they prevent others from shipping with you.--> <!-- (`mitigate:solo-deploy`) -->
- **Feature Flag** - Change can be disabled by feature flag, but will need to be rolled back if the feature flag does not work. [add DevPortal link here] <!-- Most production changes should be protected by feature flag(s). --> <!-- (`mitigate:feature-flag`) -->
- **Rollback** - Change can only be disabled by [rolling back](https://ops.githubapp.com/docs/playbooks/github_deployments.md) the merge group, or by deploying a revert commit. <!-- (`mitigate:rollback`) -->

---

<!-- Authors: Please fill out this form carefully and completely. See also https://thehub.github.com/engineering/development-and-ops/deployment/deploying-dotcom/ -->

_**Reviewers:** Please read carefully. By approving, you support the deployment and mitigation plans as well as the code change. If anything is unclear or missing, please ask for updates._

<!-- Authors: Please do not modify this line: pull_request_template_version=2

For those looking to modify this template, please see the following workflow file for additional comments: .github/workflows/label_pr_from_template.yml
-->
