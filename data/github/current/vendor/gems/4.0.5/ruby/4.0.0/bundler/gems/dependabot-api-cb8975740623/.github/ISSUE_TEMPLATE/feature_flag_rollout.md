---
name: Feature Flag Rollout
about: Process for rolling out an individual Feature Flag
title: '[FF] '
labels: 'feature flag'
assignees: ''

---

### What is the name of your feature flag?

<!-- Also include a link to the devtools page for your feature flag
     https://admin.github.com/devtools/feature_flags -->

### What is its purpose?

<!-- Describe the behavior with the Feature Flag enabled or disabled -->

### What observability will be used during rollout?

<!-- Add links to relevant dashboars and/or notebooks used to monitor the rollout -->

### Is there a Planned Event?

<!-- For any significant rollout, consider scheduling a planned event -->
<!-- https://thehub.github.com/epd/engineering/incident-response/tooling/creating-a-planned-event/ -->
<!-- If yes, link it here. -->

### Feature Flag Rollout Checklist

_See feature flag documentation [here](https://thehub.github.com/epd/engineering/products-and-services/dotcom/features/feature-flags/)._


<!-- The following checklist is from the documentation linked above. Use this as a starting point for your rollout plan. Add additional steps if necessary -->

- [ ] Develop and test your changes locally. You can enable the feature flag in local developer environments for test purposes.
- [ ] Create a feature flag that is fully disabled for everyone and use it to control access to your new feature.
- [ ] Make sure that you test your code with the feature flag enabled and disabled to make sure both sides of the flag operate as expected with your changes. Add these tests to your test suite.
- [ ] (Suggested) Schedule a [Planned Event](https://thehub.github.com/epd/engineering/products-and-services/dotcom/features/feature-flags/) for your rollout.
- [ ] Deploy your software to all environments with the feature flag fully disabled.
- [ ] Enable your feature flag for a limited testing audience to build confidence. Examples are staff shipping using the preview_features group or directly assigning access to a small subset of users/repos/businesses.
- [ ] Slowly roll out your flag across environments by slowly incrementing access to wider audiences. This can be done with percentage of users or percentage of calls increases (e.g. 2%, 10%, 30%, 50%, etc.). If you detect any problems you can immediately reduce your rollout percentage or fully disable the feature flag. Various rollout strategies are possible using the different capabilities of the feature flag control gates (percentages, actors, custom groups, targeting specific environments like dotcom/proxima stamps).
- [ ] At each stage of rollout monitor your changes for impacts to defects, error rates, performance and resource demands.
- [ ] Once you have confidence in your feature and no reported or observed issues fully enable your feature flag for all environments.
- [ ] For a period of time monitor the feature flag for stability and schedule removal of the feature flag after a minimum of two weeks of stability. First remove the conditional code that uses the feature flag and once all of it is deployed and showing no impacts, remove the feature flag itself.
