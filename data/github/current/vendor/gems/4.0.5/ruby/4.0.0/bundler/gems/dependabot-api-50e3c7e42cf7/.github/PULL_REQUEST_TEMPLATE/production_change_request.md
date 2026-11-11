_Authors: Please fill out this form carefully and completely._

_Reviewers: By approving this Pull Request you are approving the production change, as well as its deployment and mitigation plans._
_Please read this description carefully. If you feel there is anything unclear or missing, please ask for updates._

### What are you trying to accomplish?

<!-- Provide a description of the changes, including any screenshots, videos, or graphs if applicable. -->
<!-- This can be cut and paste from your Production Change Request document, included in this PR. -->
<!-- See the template [here](/pcrs/TEMPLATE.md) -->

#### Which environments does this change target?

<!-- which environments does this change impact? Select or unselect all that apply. -->
- [ ] dependabot-api production
- [ ] dependabot-api proxima

#### List the issues that this change affects.

  <!--Every production change should be tracked by _at least 1_ issue. Fixes a bug, completes a task, every change
      should have a corresponding issue listed here. If one does not already exist, please create one. -->

#### Risk Assessment

  <!-- Please select from one of the following and detail why this level was chosen -->
  <!-- Check out https://thehub.github.com/engineering/products-and-services/dotcom/pr-risk-and-rollout-review/#evaluate-the-pr-for-the-level-of-risk-it-presents for more details on risk assessment. -->
  <!-- This should match what is in the Production Change Request document. -->

- [ ] **Low risk** the modifications are small, highly observable, and easily rolled back.
- [ ] **Medium risk** changes that are isolated, reduced in scope or could impact few users and not bring the site down.
- [ ] **High risk** changes are those that could impact our customers and SLOs, low or no test coverage, low observability, or slow to rollback.

### Anything you want to highlight for special attention from reviewers?

<!-- This is your chance to identify remaining risks and confess any uncertainties you may have about the correctness of the changes.
     Highlight anything on which you would like a second (or third) opinion.
     Keep in mind how much traffic will be affected by your changes when assessing risk. -->
