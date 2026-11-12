# ExP data pipeline

Last updated: 2025-07-30

According to ExP’s [data contract](https://eng.ms/docs/products/experimentation-platform/docs/datasources/datacontract), there are several required fields that must appear across all rows of telemetry used in scorecard calculation. They can be added through data cooking rather than coming directly from the product: 

* **Randomization unit ID**: This is the identifier passed to treatment assignment for randomization into experiment variants. This value must be non-null across all telemetry.   
* **Assignment context**: A value that comes from the treatment assignment response that indicates what experiments the unit belongs to.   
* **Event received time**: Timestamp for each of the rows of telemetry. This is recommended to be a server timestamp due to data quality issues that come from client timestamps.   
* **Aggregation columns**: Columns used to group by to calculate metrics. 

Based on these requirements and anticipated needs for metric design, we have designed the following recommended schema which follows the design of other GitHub ExP pipelines and tables.

# Pipeline overview

Generally, data is pulled from several hydro topics which primarily include sweagentd topics ([source](https://github.com/github/hydro-schemas/tree/b67dbe5f4c531a4ecfa824812b0c0512314d7655/proto/hydro/schemas/sweagentd/v0)) and pull request topic ([source](https://github.com/github/hydro-schemas/blob/main/proto/hydro/schemas/github/v1/entities/pull_request.proto)). Data is preprocessed and written to intermediate tables in the copilot\_exp database and then finally exported to an Azure storage account (read more [here](https://github.com/github/copilot/blob/main/docs/online-experiments/pipeline_dataflow.md)).

**⚠️WARNING: This is subject to change as we build out P0 metrics ⚠️**

There are three tables that feed into the ExP data source. The Airflow [DAG](https://github.com/github/airflow-sources/blob/master/dags/copilot/measurement_and_eval/exp/copilot_exp_padawan.py) handles the scheduling and exporting of this data.

1. The \`exp\_data\_padawan\_telemetry\` table  
   * sweagentd data including sweagentd\_v0\_job\_started, sweagentd\_v0\_job\_completed, sweagentd\_v0\_telemetry  
   * The query that populates it is defined [here](https://github.com/github/warehouse-config/blob/main/kusto/ghdwprod/copilot_exp/functions/exp_pipelines_padawan_telemetry.yml)  
2. The \`exp\_data\_padawan\_prs\` table  
   * Pull request data to get the states of a PR. Note that the raw telemetry does not have information linking back to the Padawan event so there are joins to get the data associated with the state at issue assigned ([example](https://github.com/github/warehouse-config/blob/902b3e1b3effbb48ead57c009985175198296681/kusto/ghdwprod/copilot_exp/functions/exp_pipelines_padawan_prs.yml#L151-L155))  
   * The query that populates it is defined [here](https://github.com/github/warehouse-config/blob/main/kusto/ghdwprod/copilot_exp/functions/exp_pipelines_padawan_prs.yml)  
3. The \`exp\_data\_padawan\_all\` table  
   * This is a union of the previous two tables. In the future, it may include additional data from other hydro topics (such as CI checks, GitHub Issue data, etc)  
   * The query that populates it is defined [here](https://github.com/github/warehouse-config/blob/main/kusto/ghdwprod/copilot_exp/functions/exp_pipelines_padawan_all.yml)

# Filters

The ExP pipeline excludes the following events if:

* user\_dotcom\_id is missing   
* pr\_id is missing  
* The activity happened in a Padawan team repo (defined [here](https://github.com/github/warehouse-config/blob/c0dec098dd7dc4e2eac89b8456edcd8cf3aee0cb/kusto/ghdwprod/copilot_exp/functions/exp_pipelines_padawan_telemetry.yml#L6-L10))

# Commonly used terms

* Job refers to the Padawan job (ie a “task” assigned to Copilot. Issue assigned is a job and so is responding to a user comment). A single PR can have multiple jobs but a job should be tied to a single PR.

# Schema

* timestamp: when the event happened  
* name: name of the event   
* user\_dotcom\_id: The GitHub dotcom\_id associated with the job actor  
* job\_id: The id for the job which can be used to link back to job\_started, job\_completed, telemetry, etc  
* repo\_id  
* pr\_id: The id for the pull request what the job is working on. For \`ISSUE\_ASSIGNED\`, this is the PR that was created. For \`PULL\_REQUEST\_COMMENT\_CREATED\`, this this the PR where the comment was made.   
* assignment\_context: placeholder until we have the assignment string  
* event\_properties  
* event\_measurements

<img width="1446" height="89" alt="image" src="https://github.com/user-attachments/assets/710fa59a-88d4-45bf-bcb0-1bf50e9e2900" />


# Data Dictionary

## Property bags (WIP)

Most other extra information is stored in one of two bags: event\_properties and event\_measurements which is sent to ExP as a string. 

### Job data

Defined [here](https://github.com/github/hydro-schemas/blob/main/proto/hydro/schemas/sweagentd/v0/entities/job.proto)

#### event\_properties

* job\_workflow\_run\_id  
  * The ID of the workflow run that was started, or the Compute ID  
* job\_create\_at  
  * Timestamp when the job was created  
* job\_owner\_id  
  * The id of the owner of the repository   
* Job\_actor\_id  
  * The dotcom ID of the user who initiated this job.

### sweagentd\_v0\_job\_started

#### event\_properties

* trigger\_type:   
  * what triggered the job start ([source](https://github.com/github/hydro-schemas/blob/b67dbe5f4c531a4ecfa824812b0c0512314d7655/proto/hydro/schemas/sweagentd/v0/entities/job_trigger.proto#L9-L15))  
  * Only available in the \`sweagentd\_v0\_job\_started\` topic  
  * \`ISSUE\_ASSIGNED\`: issue is assigned to the agent  
  * \`PULL\_REQUEST\_COMMENT\_CREATED\`: dev requests changes in PR as a comment  
  * \`PULL\_REQUEST\_REVIEW\_SUBMIT\`: dev requests changes to PR via a PR review  
  * \`CODE\_SCANNING\_ALERTS\_ASSIGNED\`  
  * API\_CALL\_RECEIVED: An issue is assigned to Copilot via API call  
* action  
  * The action that the agent takes when it is triggered ([source](https://github.com/github/sweagentd/blob/3ea57a606bc004d023de54deafabfe422f8d2e22/internal/jobs/jobs.go#L167-L175)). Only available for job\_created events  
  * \`FIX\` is the action taken when the issue is assigned to the agent.   
  * \`FIX\_PR\_COMMENT\` is the action taken when the agent is triggered by an actionable comment or review on a PR. The agent will reply directly to the review comment.  
* job\_created\_at  
  * When the job was created (used to calculate TimeToX measurements)  
* job\_created\_pr  
  * A calculated bool field indicating whether the job created a PR (versus running a job on an existing PR).   
  * This is important because assignment happens when issues are assigned / PR is created. Accurately measuring this helps indicate health of assignment. 

### sweagentd\_v0\_job\_completed

* Filtered to terminal\_state \== ‘COMPLETED’ ([source](https://github.com/github/hydro-schemas/blob/main/proto/hydro/schemas/sweagentd/v0/entities/job_terminal_state.proto))  
* Job properties are not provided for this event so we join back to sweagentd\_v0\_job\_started events to get information such as job\_actor, etc

#### event\_measurements

* time\_to\_complete\_s  
  * From \`duration\_sec\` hydro field  
  * the time taken from job creation to job completion

### sweagentd\_v0\_telemetry

In the pipeline, only specifics event types are included \`kind in ("get\_completion\_with\_tools\_turn","tool\_call\_executed","online_eval_hardness","online_eval_quality","online_eval_trajectory")\`

#### event\_properties

* tool\_call\_model  
  * Relevant for kind \== ‘get\_completion\_with\_tools\_turn’  
  * Name of the model used for the tool call  
* tool\_call\_agent  
* tool\_turn\_error  
* tool\_result\_type

#### event\_measurements

* retries\_used  
* turn\_duration\_ms  
* response\_completion\_tokens  
* response\_prompt\_tokens

### copilot\_swe\_agent\_v0\_feedback

* Events related to users providing a thumbs up or thumbs down. This is currently mapping back on the PR level (not the comment-level).  
* This happens after run time so assignment context and job information is not provided. The pipeline joins these events back to job\_started events based on the pull\_request\_id.

#### event\_properties

* feedback\_analytics\_trackingid  
  * analytics tracking id of the user who gave the feedback  
* feedback\_target\_id  
* feedback\_target  
* feedback\_type  
  * ‘NEGATIVE’ or ‘POSITIVE’ based on the rating

### Pull Request data

PR data lags from the swe agent data because most of the data is state wise and lags from the original job. 

### github\_v1\_pull\_request\_create

#### event\_properties

* pr\_author\_id  
  * Dotcom\_id of the user who created the PR (should be tied to sweagent)  
* pr\_state  
  * The state of the PR (should be “OPEN” for newly created PRs  
* repo\_owner\_id  
  * The dotcom\_id of the owner of the repo

#### event\_measurements

* pr\_body\_size  
  * The issue body size at time of PR creation. Since CCA has a generic body that is updated once the job is complete, use this measure with caution

### github\_v1\_pull\_request\_merge

#### event\_properties

* pr\_author\_id  
  * Dotcom\_id of the user who created the PR (should be tied to sweagent)  
* pr\_merge\_actor\_id  
  * The dotcom\_id of the user who merged the PR  
* pr\_merged\_at  
  * The timestamp of the merge event

#### event\_measurements

* pr\_body\_size  
  * The issue body size at time of the PR event  
* pr\_total\_commits  
  * The total number of commits (by any actor) for the PR  
* pr\_created\_to\_merge\_s  
  * The duration in seconds between the time the PR was created to merged

### github_v1_pull_request_close
Events that are explicit closing of PR (i.e. abandoned)

#### event\_properties
* head_sha
  * The head sha (sha after changes) for the event. You can use this to link to commit history.
* base_sha
  * The base sha (prior to changes) for the event. You can use this to link to commit history.

#### event\_measurements
* pr_created_to_close_s
  * duration in seconds from PR creation to close
 
#### github_v1_pull_request_ready_for_review

Events related to switching a PR to ready for review (which is done by a user).


#### github_v1_pull_request_synchronize
Events related to PR synchronizing due to a new commit (or rebase). There is currently a filter to only include commits made by the agent. This is used to link back to commit info. 

#### github_v1_post_receive_commit
Events on the commmit such as lines added/delted/modified.

#### github_v1_check_suite_status_change
Used to get the check_suites initiated for each sha. 

#### github_actions_v0_compute_usage
Events on the conclusion of actions runs. Joined with `github_v1_check_suite_status_change` to get the state of CI checks (passed/failed/skipped).




