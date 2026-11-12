# Copilot Coding Agent Experimentation Guide  
This document provides step-by-step guidelines / recommendations for setting up, running, and monitoring experiments for the CCA. 
**Quick Table of Contents**
- [How to set up an experiment in ExP](#how-to-set-up-an-experiment)
- [FAQs](#faqs)
- [Simplified Process Guide](#simplified-process-guide)
  - [Step 1: Propose Experiment](#step-1-propose-experiment)
  - [Step 2: Get Approvals](#step-2-get-approvals)
  - [Step 3: Begin Experiment](#step-3-begin-experiment)
  - [Step 4: Monitor Experiment](#step-4-monitor-experiment)
  - [Step 5: End Experiment & Document Findings](#step-5-end-experiment--document-findings)


# How to set up an experiment in ExP

Also see the [completions experimentation quickstart guide](https://github.com/github/copilot/blob/main/docs/online-experiments/experimentation_quickstart.md) and [setup guide](https://github.com/github/copilot/blob/main/docs/online-experiments/guides/01_exp_setup_launch_monitoring.md) (old UI but guidance still applies)

1. [Create a new experiment](https://eng.ms/docs/products/experimentation-platform/docs/experimentauth/createfeatureexperiment-newexp_part)  
   1. Experimentation group: `vscodeexpws~padawan`  
   2. Description: Include the github tracking issue in the description  
   3. Subscribers: users you want to be notified of experiment start, stop, and progression  
   4. Isolation group: Usually, select `Auto generated Isolation Group`. If your flight might overlap with another feature, there is an option to `Use custom Isolation Group`  
2. [Create flights (aka variants)](https://eng.ms/docs/products/experimentation-platform/docs/experimentauth/editfeaturevariants-newexp_part)  
   1. We recommend variant names that follow this convention: ghpad\_\#\#\#\#\_t for treatment and ghpad\_\#\#\#\#\_c for control, with \#\#\#\#\# being the issue number. You can add more keywords, the only limit is that flight names cannot have more than 16 characters. Just avoid overly specific flight names since there is a chance these could be exposed to users.  
3. [Edit the feature experiments](https://eng.ms/docs/products/experimentation-platform/docs/experimentauth/editfeatureexperiment-newexp_part)  
   1. Add feature flags to configure what is in each variant. For example, your control group might want to have the default model while your treatment might have a custom model. [Here](https://github.com/github/sweagentd/pull/5527/files) is an example PR that wires up the ExP feature flag to the client code.    
4. [Create a progression](https://eng.ms/docs/products/experimentation-platform/docs/experimentauth/addprogression-newexp_part)  
   1. A progression is how you manage where to expose your feature and in what order. For example, you may want to roll out your feature to a specific org to begin with and expose more repos later on. See more [here](https://eng.ms/docs/products/experimentation-platform/docs/experimentauth/addprogression-newexp_part)  
   2. Specify your flights in each progression (typically all)  
   3. Specify traffic filters (ex: Repository IN \`github/github\`)  
5. Update traffic steps  
   1. Choose the maximum traffic to reserve for your experiment  
   2. Initially, roll out at a small % of your max traffic to check for bugs. You can increase traffic after you’ve done checks at a lower %.  
      1. For example, you might want to do 30% of staff in treatment → 50% of staff in treatment → 5% external traffic  
6. Once this is set up, get a review on your experiment (see process guide below).   
7. Begin your experiment by clicking \`Start\`

# FAQs

1. How do I get access to ExP? 
    * Add yourself to the `VS Code ExP Contributor` [IDWeb Group](https://idweb.microsoft.com/IdentityManagement/aspx/groups/MyMemberships.aspx?popupFromClipboard=https%3A%2F%2Fidweb.microsoft.com%2Fidentitymanagement%2Faspx%2FGroups%2FEditGroup.aspx%3Fid%3D53343c08-29ed-4c47-a916-27942bb25a99%26UOCInitialTabName%3DGroupingBasicInfo)
    * Use [Azure VPN](https://github.com/github/copilot/blob/main/docs/how-tos/access-devdiv-data.md#setup-your-computer) or cloud Dev Box
2.  What are isolation groups and how should I use them?   
   * Isolation groups are an ExP feature that make it possible to run mutually exclusive experiences to prevent, for example, experiment one giving a user a black text and experiment two giving them a black background, making the text unreadable.   
   * For most experiments, some overlap is fine (testing a UI change and and underlying model change on the same PR is generally allowed). In some cases, you may want to isolate the experiments so that they are mutually exclusive.   
   * This works by setting aside a percent of traffic that falls within the isolation group. For example, you may have a CustomModel isolation group that reserves 20% of traffic. Experiments that run within that isolation group will reserve a portion of the reserved traffic. Read more [here](https://microsoft-my.sharepoint.com/:w:/p/camitche/EY8eiccvFtxPi3LRegqumwQBI1QeNqfhWXe6J4WoJSWKpg)  
3. I’m getting paged for failures and I think it has to do with an experiment.   
   * If you know which experiment is causing the issue, you can just STOP the experiment. You can see all active CCA experiments [here](https://exp.microsoft.com/feature-search?workspaceId=dbd12384-5001-4e90-a863-526321eaf233&_treatmentVariable=forceUnifiedView:true&experimentationGroup=vscodeexpws~padawan&statuses=running) (log in with your \`@[microsft.com](http://microsft.com)\` credentials. Click into the problematic experiment and click the \`STOP\` button. It is good practice to surface that decision in `#copilot-experiment-shiproom` and `#coding-agent-team`  
   * If an issue with the experimentation platform and you **absolutely** need to stop all experiments, you can disable the [copilot\_swe\_agent\_experimentation feature flag](https://devportal.githubapp.com/feature-flags/copilot_swe_agent_experimentation/overview) which will stop assignment for **all experiments**. This is not recommended as it will skew experiment data but can be leveraged if absolutely necessary. 

# Simplified Process Guide

Modified from [Completions and NES experimentation instructions](https://github.com/github/copilot/blob/main/.github/ISSUE_TEMPLATE/a-b-experiment-template.yaml) (end of template) and [Dotcom Chat’s guide](https://github.com/github/copilot-api/blob/main/docs/dotcom-chat/a-b-testing.md#adding-metrics-to-the-dotcom-chat-scorecard) to starting an experiment

## **Step 1: Propose Experiment**

1. We recommend you make an issue for each experiment for tracking purposes. You can reference the [Completions+NES template](https://github.com/github/copilot/blob/main/.github/ISSUE_TEMPLATE/a-b-experiment-template.yaml) for inspiration.   
   1. If you need help, reach out to us on Slack in `#copilot-experimentation-enablement` or join our weekly office hours (more info in our channel).  
2. Have a clear understanding of what you're hoping to learn in the experiment  
   1. Are you hoping to make a ship decision or just gather data?  
   2. What are you testing? What are your variations?  
   3. What does a “winning experiment” look like?

## **Step 2: Get Approvals**

1. Get approvals from relevant folks (managers, first responders, etc)

## **Step 3: Begin Experiment**

1. Set up experiment in ExP  
2. Post in `#padawan-evals` before launch and for any changes (traffic increase or stopped progression) to your rollout.

**Suggested Rollout Guidelines:**

1. Start **model** experiments with a low traffic rollout for an hour as a smoke test in combination with production dashboards (e.g., Datadog) for monitoring.   
2. Advance traffic as you verify capacity and product health. It is good practice to post in \#padawan-evals and/or \#coding-agent-team  
3. We recommend having someone online after the experiment launches to monitor for any potential issues. To ensure support is available if issues emerge, it's best to avoid launching on weekends or Friday afternoons.

## **Step 4: Monitor Experiment**

### **Initial Monitoring:**
Confirm within **1 hour** of launch:  
   1. Traffic is flowing.  
   2. Error rates are stable.  
   3. If errors are high, ABORT & debug.

### **Regular Updates:**

1. Provide a Slack update in `#padawan-evals` at each traffic ramp-up stage. This is especially helpful for folks on-call. 
2. It is good practice to provide updates on progress in the comments of this issue.

## **Step 5: End Experiment & Document Findings**

1. Close the experimentation issue.  
2. Write findings and conclusions (ship / no ship) in the issue.

