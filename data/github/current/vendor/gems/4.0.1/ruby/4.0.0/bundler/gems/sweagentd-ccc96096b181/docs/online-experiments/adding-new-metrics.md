# Adding metrics to the Padawan ExP scorecard

Instructions on how to add A/B testing metrics for Copilot Coding Agent  
Also see [Dotcom Chat’s playbook for adding metrics](https://github.com/github/copilot-api/blob/main/docs/dotcom-chat/a-b-testing.md#adding-metrics-to-the-dotcom-chat-scorecard) 

# Pre-requisites 

* Access to GitHubCopilot\_Padawan\_v1 [ExP metric set](https://exp.microsoft.com/metric-set/GitHubCopilot_Padawan_v1?workspaceId=dbd12384-5001-4e90-a863-526321eaf233&_treatmentVariable=forceUnifiedView:true) (use @[microsoft.com](http://microsoft.com) credentials)
   * If you don't have access to ExP, add yourself to the `VS Code ExP Contributor` [IDWeb Group](https://idweb.microsoft.com/identitymanagement/aspx/groups/MyMemberships.aspx?popupFromClipboard=%2Fidentitymanagement%2Faspx%2FGroups%2FEditGroup.aspx%3Fid%3D53343c08-29ed-4c47-a916-27942bb25a99)
* Access to [Azure Dev Ops repo](https://dev.azure.com/githubcopilotexp/ExP%20Metric%20Sets/_git/GitHubCopilot_Padawan_v1) for metric set (use @[microsoft.com](http://microsoft.com) credentials)  

# Overview of Steps

In order to add or change metrics that appear on the ExP scorecard the following has to happen:

1. The telemetry used to calculate the metric must be in the ExP data pipeline and table. You can read more about the shaped data [here](https://github.com/github/sweagentd/tree/main/docs/online-experiments/data-pipeline.md).  
2. Once the data is in the pipeline, you must add the calculation to the ExP metric set which you can do [via the UI](https://eng.ms/docs/products/experimentation-platform/docs/metricauth/newmetricwizard) or directly to the [MDL Computation files](https://dev.azure.com/githubcopilotexp/ExP%20Metric%20Sets/_git/GitHubCopilot_Padawan_v1?path=/UserDefinedFiles/MDLComputations.xml).   
3. Validate the metrics

For complex metrics or if you’re new to adding metrics and need help, you can submit an [A/B Experiment Metric Request](https://github.com/github/copilot/issues/new?template=a-b-experiment-metric-request.yaml) to get help from the measurement and evaluation team. Otherwise, you can self service with the steps below/

# Detailed steps

## 1\. Update the ExP telemetry pipeline

1. **Determine if you need to update the processing queries**. Check if the queries already have the properties and/or measurements that you need.   
   1.[padawan_jobs](https://github.com/github/airflow-sources/blob/master/dags/copilot/measurement_and_eval/exp/kql/padawan/padawan_jobs.kql) includes events related to job status (such as job start end completed)
   2. [padawan\_telemetry](https://github.com/github/airflow-sources/blob/master/dags/copilot/measurement_and_eval/exp/kql/padawan/padawan_telemetry.kql) includes events that are emitted by sweagent close to run time  
   3. [padawan\_prs](https://github.com/github/airflow-sources/blob/master/dags/copilot/measurement_and_eval/exp/kql/padawan/padawan_prs.kql) includes events that are emitted after the job run. Typically, these are other GitHub topics (such as commit history, pull request state, actions, feedback, etc)  
2. **Create a PR** to update the queries in the previous step if you need to add any additional event and/or properties. A member of the @github/measurement-and-eval team will review the PR, typically between 1-2 days.  
   1. Example: [Add missing property to existing event](https://github.com/github/warehouse-config/pull/2861)

## 2\. Define new metrics in ExP

1. **Access the Metric Set**:  
   1. Navigate to "[Metric and analysis plans](https://exp.microsoft.com/metric-set?workspaceId=dbd12384-5001-4e90-a863-526321eaf233&_treatmentVariable=forceUnifiedView:true)" in ExP  
   2. Select the GitHubCopilot\_Padawan\_v1 metric set  
2. **Create a Draft Metric Set**:  
   1. This allows you to experiment without affecting current metrics  
   2. Click on "Create Draft" from the metric set page
      ![1-add-draft](https://github.com/user-attachments/assets/7396a2f4-f79e-4ec2-a3a3-a8223310bfb8)
3. **Define Your New Metric**:  
   1. Add a "Custom Column" if you need to unpack info stored in a property bag:  
      1. Go to the Computation Templates tab and use any of the templates named Unpack\<TYPE\>Property  
      2. See the [ExP docs](https://eng.ms/docs/products/experimentation-platform/docs/metricauth/language/csharpsupport) on json extraction for more info.
   ![2-add-custom-column](https://github.com/user-attachments/assets/96b9b0d3-0683-4a73-b879-af88af486a7c)

   2. Add an aggregated metric based on your column:  
      1. Leverage existing templates such as [BasicEventMetrics](https://exp.microsoft.com/metric-set/GitHubCopilot_Padawan_v1/draft/master/template?workspaceId=dbd12384-5001-4e90-a863-526321eaf233&_treatmentVariable=forceUnifiedView:true) which calculates standard columns and basic metrics based on an event type.  
      2. Alternatively, [create a custom metric](https://eng.ms/docs/products/experimentation-platform/docs/metricauth/newmetricwizard). You will need to decide on which level to aggregate (Pull Request or Job).
   ![3-add-aggregated-metric-ezgif com-speed](https://github.com/user-attachments/assets/c5363614-0cd7-4b94-87ed-866d30eace03)

4. **Update the Scorecard Layout**:  
   1. Add your metric to the [Scorecard Layout](https://eng.ms/docs/products/experimentation-platform/docs/metricauth/addmetricstolayout)  
   2. Position it logically among related metrics or create a new section  
   ![4-add-to-scorecard-layout](https://github.com/user-attachments/assets/e61a59a8-af9e-4060-ae31-4c2de10fbeb2)

5. **Validate and Publish**:  
   1. Run [validation](https://eng.ms/docs/products/experimentation-platform/docs/metricauth/generatepreviewscorecardnew) on your draft metric set  
   2. Once validation succeeds, publish the metric set
   ![5-validate-metric-set](https://github.com/user-attachments/assets/9615090f-93cb-4ee1-8824-9f8cd5dc6309)

## 3\. Validate metrics using a preview scorecard

Once your metric set is validated and published, you can create preview scorecards to validate your metrics on a smaller scale.

1. **Access the Preview Functionality** ([step 3 in ExP docs](https://eng.ms/docs/products/experimentation-platform/docs/metricauth/generatepreviewscorecardnew))  
   * Go to the "Preview Scorecard" tab, or  
   * Click "Create a preview scorecard" under the validation success message  
2. **Configure Preview Parameters**:  
   * Select an Experiment Step: Choose from an ongoing experiment (preferably an A/A or one you're involved with)  
   * Make sure you select `Preview analysis`  
   * Metric set: `GitHubCopilot_padawan_v1`  
   * Template: `GitHubCopilotPadawan.Basic`  
   * Set a custom schedule:  
     * Choose a short time period (1-2 hours) with known data availability  
     * **Note**: Longer time periods will significantly increase generation time  
3. **Simplify Segmentation**:  
   * Toggle "Default Segment"  
   * Remove added segments to reduce processing time  
   * **Important**: Each segment substantially increases scorecard generation time  
4. **Complete Setup**:  
   * Skip the Trigger/Filter page if not needed  
   * Add yourself as a subscriber (optional)  
   * Review settings and create the preview  
5. Validate results  
* Once the scorecard generates, verify your metrics appear correctly  
* Check that data values make sense and match expectations  
* Iterate on your metric definitions if needed

## 4\. Merge metric changes to Production

1. After successful validation, merge your changes to production (“Merge” in the Metrics Set UI)  
2. This will automatically create a PR for the Applied Science team to review in ADO. There will also be a notification in [\#experimentation-platform-ops](https://github-grid.enterprise.slack.com/archives/C095NQYDZ41)  
   * We recommend you update the title of the PR and include a preview scorecard linked in the description.   
3. After your PR is merged, any new scorecards will have your changes.
