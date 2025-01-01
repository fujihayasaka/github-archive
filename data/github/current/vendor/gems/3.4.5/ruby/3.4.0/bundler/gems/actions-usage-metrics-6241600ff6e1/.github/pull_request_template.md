### Context

<!--
This section ties together context explaining why this pull request exists.

Code changes should be in response to an issue. If one does not already exist, create one in the relevant repository.
Link related discussions, comments, pull requests, and feature releases (see https://github.com/github/releases#readme).
Format links with a Markdown list so that each title unfurls automatically, e.g.,
- Closes <issue URL>
- Based on <preceding pull request URL>
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
-->

### Terraform Instructions
<!-- Instructions -->

<details>
<summary>How To Deploy Terraform Changes</summary>

1. Comment `.noop` on this PR to run a no-op plan
   * If there is a lock and the `.unlock` command doesn't work, you can follow the lock link and delete the branch containing the lock file (view all branches -> delete)
2. Get a review
3. Comment `.deploy` on this PR to deploy your changes
4. Merge the pull request

</details>
