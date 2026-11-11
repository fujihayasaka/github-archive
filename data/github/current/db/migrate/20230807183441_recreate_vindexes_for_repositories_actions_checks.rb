# typed: true

class RecreateVindexesForRepositoriesActionsChecks < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesActionsChecks)

  def change
    # artifacts_id_keyspace_idx
    remove_vindex("artifacts", "artifacts_id_keyspace_idx", "id")

    drop_vindex("artifacts_id_keyspace_idx", "lookup_unique", { "from" => "id", "table" => "artifacts_id_keyspace_idx", "to" => "keyspace_id", "owner" => "artifacts" })
    create_vindex("artifacts_id_keyspace_idx", "lookup_unique", { "from" => "id", "table" => "artifacts_id_keyspace_idx", "to" => "keyspace_id", "owner" => "artifacts", "autocommit" => true, "read_lock" => "none" })

    add_vindex("artifacts", "artifacts_id_keyspace_idx", "id")

    # check_annotations_id_keyspace_idx
    remove_vindex("check_annotations", "check_annotations_id_keyspace_idx", "id")
    remove_vindex("code_scanning_alerts", "check_annotations_id_keyspace_idx", "check_annotation_id")

    drop_vindex("check_annotations_id_keyspace_idx", "lookup_unique", { "from" => "id", "table" => "check_annotations_id_keyspace_idx", "to" => "keyspace_id", "owner" => "check_annotations" })
    create_vindex("check_annotations_id_keyspace_idx", "lookup_unique", { "from" => "id", "table" => "check_annotations_id_keyspace_idx", "to" => "keyspace_id", "owner" => "check_annotations", "autocommit" => true, "read_lock" => "none" })

    add_vindex("check_annotations", "check_annotations_id_keyspace_idx", "id")
    add_vindex("code_scanning_alerts", "check_annotations_id_keyspace_idx", "check_annotation_id")

    # check_runs_id_keyspace_idx
    remove_vindex("check_annotations", "check_runs_id_keyspace_idx", "check_run_id")
    remove_vindex("check_runs", "check_runs_id_keyspace_idx", "id")
    remove_vindex("check_steps", "check_runs_id_keyspace_idx", "check_run_id")

    drop_vindex("check_runs_id_keyspace_idx", "lookup_unique", { "from" => "id", "table" => "check_runs_id_keyspace_idx", "to" => "keyspace_id", "owner" => "check_runs" })
    create_vindex("check_runs_id_keyspace_idx", "lookup_unique", { "from" => "id", "table" => "check_runs_id_keyspace_idx", "to" => "keyspace_id", "owner" => "check_runs", "autocommit" => true, "read_lock" => "none" })

    add_vindex("check_annotations", "check_runs_id_keyspace_idx", "check_run_id")
    add_vindex("check_runs", "check_runs_id_keyspace_idx", "id")
    add_vindex("check_steps", "check_runs_id_keyspace_idx", "check_run_id")

    # check_steps_id_keyspace_idx
    remove_vindex("check_steps", "check_steps_id_keyspace_idx", "id")

    drop_vindex("check_steps_id_keyspace_idx", "lookup_unique", { "from" => "id", "table" => "check_steps_id_keyspace_idx", "to" => "keyspace_id", "owner" => "check_steps" })
    create_vindex("check_steps_id_keyspace_idx", "lookup_unique", { "from" => "id", "table" => "check_steps_id_keyspace_idx", "to" => "keyspace_id", "owner" => "check_steps", "autocommit" => true, "read_lock" => "none" })

    add_vindex("check_steps", "check_steps_id_keyspace_idx", "id")

    # check_suites_id_keyspace_idx
    remove_vindex("artifacts", "check_suites_id_keyspace_idx", "check_suite_id")
    remove_vindex("check_annotations", "check_suites_id_keyspace_idx", "check_suite_id")
    remove_vindex("check_runs", "check_suites_id_keyspace_idx", "check_suite_id")
    remove_vindex("check_suites", "check_suites_id_keyspace_idx", "id")
    remove_vindex("code_scanning_check_suites", "check_suites_id_keyspace_idx", "check_suite_id")
    remove_vindex("workflow_runs", "check_suites_id_keyspace_idx", "check_suite_id")

    drop_vindex("check_suites_id_keyspace_idx", "lookup_unique", { "from" => "id", "table" => "check_suites_id_keyspace_idx", "to" => "keyspace_id", "owner" => "check_suites" })
    create_vindex("check_suites_id_keyspace_idx", "lookup_unique", { "from" => "id", "table" => "check_suites_id_keyspace_idx", "to" => "keyspace_id", "owner" => "check_suites", "autocommit" => true, "read_lock" => "none" })

    add_vindex("artifacts", "check_suites_id_keyspace_idx", "check_suite_id")
    add_vindex("check_annotations", "check_suites_id_keyspace_idx", "check_suite_id")
    add_vindex("check_runs", "check_suites_id_keyspace_idx", "check_suite_id")
    add_vindex("check_suites", "check_suites_id_keyspace_idx", "id")
    add_vindex("code_scanning_check_suites", "check_suites_id_keyspace_idx", "check_suite_id")
    add_vindex("workflow_runs", "check_suites_id_keyspace_idx", "check_suite_id")

    # code_scanning_alerts_id_keyspace_idx
    remove_vindex("code_scanning_alerts", "code_scanning_alerts_id_keyspace_idx", "id")

    drop_vindex("code_scanning_alerts_id_keyspace_idx", "lookup_unique", { "from" => "id", "table" => "code_scanning_alerts_id_keyspace_idx", "to" => "keyspace_id", "owner" => "code_scanning_alerts" })
    create_vindex("code_scanning_alerts_id_keyspace_idx", "lookup_unique", { "from" => "id", "table" => "code_scanning_alerts_id_keyspace_idx", "to" => "keyspace_id", "owner" => "code_scanning_alerts", "autocommit" => true, "read_lock" => "none" })

    add_vindex("code_scanning_alerts", "code_scanning_alerts_id_keyspace_idx", "id")

    # code_scanning_check_suites_id_keyspace_idx
    remove_vindex("code_scanning_check_suites", "code_scanning_check_suites_id_keyspace_idx", "id")

    drop_vindex("code_scanning_check_suites_id_keyspace_idx", "lookup_unique", { "from" => "id", "table" => "code_scanning_check_suites_id_keyspace_idx", "to" => "keyspace_id", "owner" => "code_scanning_check_suites" })
    create_vindex("code_scanning_check_suites_id_keyspace_idx", "lookup_unique", { "from" => "id", "table" => "code_scanning_check_suites_id_keyspace_idx", "to" => "keyspace_id", "owner" => "code_scanning_check_suites", "autocommit" => true, "read_lock" => "none" })

    add_vindex("code_scanning_check_suites", "code_scanning_check_suites_id_keyspace_idx", "id")

    # commit_rollups_id_keyspace_idx
    remove_vindex("commit_rollups", "commit_rollups_id_keyspace_idx", "id")

    drop_vindex("commit_rollups_id_keyspace_idx", "lookup_unique", { "from" => "id", "table" => "commit_rollups_id_keyspace_idx", "to" => "keyspace_id", "owner" => "commit_rollups" })
    create_vindex("commit_rollups_id_keyspace_idx", "lookup_unique", { "from" => "id", "table" => "commit_rollups_id_keyspace_idx", "to" => "keyspace_id", "owner" => "commit_rollups", "autocommit" => true, "read_lock" => "none" })

    add_vindex("commit_rollups", "commit_rollups_id_keyspace_idx", "id")

    # statuses_id_keyspace_idx
    remove_vindex("statuses", "statuses_id_keyspace_idx", "id")

    drop_vindex("statuses_id_keyspace_idx", "lookup_unique", { "from" => "id", "table" => "statuses_id_keyspace_idx", "to" => "keyspace_id", "owner" => "statuses" })
    create_vindex("statuses_id_keyspace_idx", "lookup_unique", { "from" => "id", "table" => "statuses_id_keyspace_idx", "to" => "keyspace_id", "owner" => "statuses", "autocommit" => true, "read_lock" => "none" })

    add_vindex("statuses", "statuses_id_keyspace_idx", "id")

    # workflow_job_runs_id_keyspace_idx
    remove_vindex("workflow_job_runs", "workflow_job_runs_id_keyspace_idx", "id")

    drop_vindex("workflow_job_runs_id_keyspace_idx", "lookup_unique", { "from" => "id", "table" => "workflow_job_runs_id_keyspace_idx", "to" => "keyspace_id", "owner" => "workflow_job_runs" })
    create_vindex("workflow_job_runs_id_keyspace_idx", "lookup_unique", { "from" => "id", "table" => "workflow_job_runs_id_keyspace_idx", "to" => "keyspace_id", "owner" => "workflow_job_runs", "autocommit" => true, "read_lock" => "none" })

    add_vindex("workflow_job_runs", "workflow_job_runs_id_keyspace_idx", "id")

    # workflow_runs_id_keyspace_idx
    remove_vindex("workflow_job_runs", "workflow_runs_id_keyspace_idx", "workflow_run_id")
    remove_vindex("workflow_run_executions", "workflow_runs_id_keyspace_idx", "workflow_run_id")
    remove_vindex("workflow_runs", "workflow_runs_id_keyspace_idx", "id")

    drop_vindex("workflow_runs_id_keyspace_idx", "lookup_unique", { "from" => "id", "table" => "workflow_runs_id_keyspace_idx", "to" => "keyspace_id", "owner" => "workflow_runs" })
    create_vindex("workflow_runs_id_keyspace_idx", "lookup_unique", { "from" => "id", "table" => "workflow_runs_id_keyspace_idx", "to" => "keyspace_id", "owner" => "workflow_runs", "autocommit" => true, "read_lock" => "none" })

    add_vindex("workflow_job_runs", "workflow_runs_id_keyspace_idx", "workflow_run_id")
    add_vindex("workflow_run_executions", "workflow_runs_id_keyspace_idx", "workflow_run_id")
    add_vindex("workflow_runs", "workflow_runs_id_keyspace_idx", "id")

    # workflow_run_executions_id_keyspace_idx
    remove_vindex("workflow_run_executions", "workflow_run_executions_id_keyspace_idx", "id")

    drop_vindex("workflow_run_executions_id_keyspace_idx", "lookup_unique", { "from" => "id", "table" => "workflow_run_executions_id_keyspace_idx", "to" => "keyspace_id", "owner" => "workflow_run_executions" })
    create_vindex("workflow_run_executions_id_keyspace_idx", "lookup_unique", { "from" => "id", "table" => "workflow_run_executions_id_keyspace_idx", "to" => "keyspace_id", "owner" => "workflow_run_executions", "autocommit" => true, "read_lock" => "none" })

    add_vindex("workflow_run_executions", "workflow_run_executions_id_keyspace_idx", "id")

    # workflows_id_keyspace_idx
    remove_vindex("workflow_runs", "workflows_id_keyspace_idx", "workflow_id")
    remove_vindex("workflows", "workflows_id_keyspace_idx", "id")

    drop_vindex("workflows_id_keyspace_idx", "lookup_unique", { "from" => "id", "table" => "workflows_id_keyspace_idx", "to" => "keyspace_id", "owner" => "workflows" })
    create_vindex("workflows_id_keyspace_idx", "lookup_unique", { "from" => "id", "table" => "workflows_id_keyspace_idx", "to" => "keyspace_id", "owner" => "workflows", "autocommit" => true, "read_lock" => "none" })

    add_vindex("workflow_runs", "workflows_id_keyspace_idx", "workflow_id")
    add_vindex("workflows", "workflows_id_keyspace_idx", "id")
  end
end
