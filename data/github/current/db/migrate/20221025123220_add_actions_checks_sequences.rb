# typed: true

class AddActionsChecksSequences < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::RepositoriesActionsChecks)

  def change
    add_auto_increment(:artifacts, :id, :artifacts_id_seq)
    add_auto_increment(:check_annotations, :id, :check_annotations_id_seq)
    add_auto_increment(:check_runs, :id, :check_runs_id_seq)
    add_auto_increment(:check_steps, :id, :check_steps_id_seq)
    add_auto_increment(:check_suites, :id, :check_suites_id_seq)
    add_auto_increment(:code_scanning_alerts, :id, :code_scanning_alerts_id_seq)
    add_auto_increment(:code_scanning_check_suites, :id, :code_scanning_check_suites_id_seq)
    add_auto_increment(:commit_rollups, :id, :commit_rollups_id_seq)
    add_auto_increment(:statuses, :id, :statuses_id_seq)
    add_auto_increment(:workflow_job_runs, :id, :workflow_job_runs_id_seq)
    add_auto_increment(:workflow_run_executions, :id, :workflow_run_executions_id_seq)
    add_auto_increment(:workflow_runs, :id, :workflow_runs_id_seq)
    add_auto_increment(:workflows, :id, :workflows_id_seq)
  end
end
