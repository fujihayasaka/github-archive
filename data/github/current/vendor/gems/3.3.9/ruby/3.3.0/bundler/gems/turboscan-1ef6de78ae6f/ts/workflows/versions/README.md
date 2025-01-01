# Creating, Testing, and Rolling out a new workflow template version

## Context

When a repository opts-in to use the default code-scanning setup, turboscan will manage the analyses and build a workflow content to send dynamically to actions to run it.
The base version of this workflow file, is called the workflow template, and that can have many versions.
Recent versions are stored in this folder (i.e.,  [ts/workflows/versions/](https://github.com/github/turboscan/tree/main/ts/workflows/versions)).

We want customers to be using the latest versions. Therefore, we upgrade their template when:

* They onboard (manually or automatically) to Default Setup
* They push to the default branch (JIT upgrade)

If the JIT upgrade fails, we will keep the repository on the previous version. We will retry the upgrade on the next push after some waiting time and for a limited amount of times.
This means that we cannot guarantee that all repos are using the same workflow template versions.

The workflow template is based on the [advanced setup starter-workflow](https://github.com/actions/starter-workflows/blob/main/code-scanning/codeql.yml). However they are not exactly the same as we have special considerations that only apply to default setup and more freedom in defining conditional logic.
Everytime the codeql starter workflow is updated, we need to consider whether we need to backport the changes to our template.

## Creating a new workflow template version

Start:

- Create a new template file under `ts/workflows/versions/` with the format 'vN.codeql.template'. For example: `ts/workflows/versions/v1.codeql.template`
- Copy one of the other version templates, and avoid drastic changes.
- Include a diff of the two workflow templates in the PR description.
- (Optional but recommended) Use one of the `.expected` files to run the workflow on a test repo. This requires committing a yml file to the test repo, and triggering it. This is particularly useful if we are leveraging new CodeQL features, so we can validate that everything works.

Testing in production:

- Make sure that the [`code_scanning_workflow_upgrade_next`](https://devportal.githubapp.com/feature-flags/code_scanning_workflow_upgrade_next/overview) is set to 0% enablement.
- Set the value of `NextVersion` (in `library.go`) to the new version.
- Deploy a PR containing the new template and the `NextVersion` change.
- Enable the FF on one or more test repos, and validate the changes.

Roll-out:

- Roll out the `code_scanning_workflow_upgrade_next` feature flag to 100%.
- Watch [this graph](https://app.datadoghq.com/dashboard/gu7-k7q-su8/managed-analyses?fromUser=false&refresh_mode=paused&tile_focus=1432664548524318&view=spans) to monitor the JIT validation failure rate for this workflow template version versus the previous version. As a general guideline, the JIT validation failure rate should stay below 3% when viewed in the 1h time window.

Once you are confident with the rollout, we can promote this version:

- Offboard/onboard the codeql-action test repos defined in [codeql-action-default-setup-test.yml](https://github.com/github/semmle-code/blob/main/.github/workflows/codeql-action-default-setup-test.yml#L69) (under `REPOSITORIES_JSON`) to ensure they are using the latest template.
- Set the value of `StableVersion` to the new version, set `NextVersion = StableVersion`, fix tets and deploy.
- Finally, set [`code_scanning_workflow_upgrade_next`](https://devportal.githubapp.com/feature-flags/code_scanning_workflow_upgrade_next/overview) to 0%

See this [commit](https://github.com/github/turboscan/pull/4087/commits/6d7ad340151cd2b403dfaa834c3056f525d1ba4f) as an example on how to write a new template with tests.

### How do I know if the upgrade has been a success?

Once the feature flag has been enabled you should start to see runs using the new template in [this graph](https://app.datadoghq.com/s/59fe6c40c/mpg-r8e-yum). After 24 hours the majority of the runs (>80%) should be using the new version, and the most active repos had a chance to upgrade to the latest version.[^1]

Once this is the case, the value of `StableVersion` should be set to the new version, and `NextVersion` should be set to `StableVersion` ([example](https://github.com/github/turboscan/pull/4313/files#diff-7454fca0fe42273044c216a24750661dc03ce20cd86464752060caa79ca5fe67)). **Important**: after this, the feature flag should be set to 0% again - don't worry, straggler repositories will still be upgraded after this!

- [This query](https://data.githubapp.com/sql/share/06c62c97) can be used to check the number of repositories using each historical workflow template version. It depends on a snapshot of the db that gets updated daily, so don't worry if the new template doesn't appear there immediately.
- The following query can be run [in the production db](https://github.com/github/ops/blob/master/docs/playbooks/github/code-scanning/runbook.md#turboscan) to check the number of active repositories (the ones which had a workflow run at least once in the last) using each historical workflow template version.

```sql
SELECT \
  COUNT(id), \
  COUNT(id) * 100 / (SELECT COUNT(id) FROM ts_codeql_configs WHERE tag = 0 AND id IN (SELECT DISTINCT codeql_config_id FROM ts_codeql_runs WHERE created_at > (current_date - interval '1' month))) AS percentage, \
  template_version \
FROM ts_codeql_configs \
WHERE \
  tag = 0 \
  AND id IN (SELECT DISTINCT codeql_config_id FROM ts_codeql_runs WHERE created_at > (current_date - interval '1' month)) \
GROUP BY template_version;
```

Here is a more readable equivalent query (but not runnable in our db):

```sql
WITH
  active_repos AS (
    SELECT ts_codeql_configs.id, ts_codeql_configs.template_version
    FROM ts_codeql_runs
    JOIN ts_codeql_configs ON ts_codeql_configs.id = ts_codeql_runs.codeql_config_id
    WHERE ts_codeql_configs.tag = 0
    AND ts_codeql_runs.created_at > (current_date - interval '1' month)
    GROUP BY 1, 2
)

SELECT
    template_version
    , COUNT(id) AS total
    , COUNT(id) * 100 / (SELECT COUNT(id) FROM active_repos) AS percentage
FROM active_repos
GROUP BY template_version;
```

[^1]:Because we only attempt the upgrade on pushes to the default branch (and _sometimes_ on manual updates to the config), and repos can go arbitrarily long without one of these, we can't expect to have 100% of repositories on the latest workflow version.

### What to do if something goes wrong

If something goes wrong, we will most likely notice it during the rollout phase, and turn the feature flag enablement back down to 0%.

While we number our workflow templates sequentially, we are not encoding that information in our logic. This means that setting the FF to 0% will lead to the rollout of the previous template (rollback).

After fixing the problem with the template, please use a new version number, as this will force all repos to upgrade (even the ones that might have failed the rollback).

TODO: We want to improve our observabilty on failed runs.

### How to resolve workflow template conflicts in your PR

- [Read here](resolving_workflow_conflicts.md)
