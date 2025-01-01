# Billing Deployments

## Dotcom deployments

If you need to deploy your changes to github/github, consider deploying them first to the review-lab environment for testing.

Note that you cannot test stafftools changes in review-lab.

To deploy to review lab, go to the [#dotcom-environment-ops](https://github.slack.com/archives/C03KHT6GS2X) Slack channel and deploy your PR (after it has passed all CI checks and reviews) using:

```
.deploy [your github/github PR URL] to review-lab
```

If all the changes look good, click the merge button. Merging your PR to github/github will add it to the merge queue. Slack will prompt you with the observability tools to monitor your deployment. You can also head to [#dotcom-ops](https://github.slack.com/archives/C0FNNUEV7) slack channel to observe the progress.

Read more about the Dotcom and Proxima deployments [here](https://thehub.github.com/epd/engineering/devops/deployment/deploying-dotcom/).

### Dotcom feature flags

The Hub has useful [documentation](https://thehub.github.com/epd/engineering/products-and-services/dotcom/features/feature-flags/) on using feature flags in dotcom.

The billing team uses a slightly different approach:

- Declare your feature flag in the PR: [good FF PR example](https://github.com/github/github/pull/328820);

- Go to the [dev portal](https://devportal.githubapp.com/feature-flags) and follow the instructions on how to add your feature flag. When asked which slack channel to list as contact, use #billing-ops or #billing-engineering. The feature flag dev portal can be used to test your changes in review-lab as well as production.

## Billing-platform deployments

Currently, there is no staging or 'review-lab' environment for the billing-platform. The changes will be deployed to all the production environments on your PR merge. You can monitor the deployment in the [#billing-platform-ops](https://github.slack.com/archives/C045DAX94JG) slack channel.

## Billing-platform feature flags

The billing-platform supports feature flags. More information can be found [here](feature-flags.md#feature-flags-in-billing-platform).
