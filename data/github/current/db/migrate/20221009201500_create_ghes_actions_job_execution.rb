# typed: true
class CreateGhesActionsJobExecution < ActiveRecord::Migration[7.1]
  def change
    create_table :ghes_actions_job_executions, id: false, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column :id, "BIGINT(20) UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY"
      t.column :event_id, "BINARY(16)", null: false
      t.string :invoking_event_type, limit: 50, null: false
      t.column :workflow_repository_id, "BIGINT(20) UNSIGNED", null: false
      t.string :workflow_repository_global_id, limit: 50, null: false
      t.string :workflow_repository_visibility, limit: 50, null: false
      t.column :workflow_build_id, "BIGINT(20) UNSIGNED", null: false
      t.string :job_id, limit: 50, null: false
      t.string :job_runtime, limit: 50, null: false
      t.string :job_runtime_version, limit: 50
      t.column :job_check_suite_id, "BIGINT(20) UNSIGNED"
      t.column :job_check_run_id, "BIGINT(20) UNSIGNED", null: false
      t.datetime :started_at, precision: 6, null: false
      t.datetime :finished_at, precision: 6, null: false
      t.column :job_execution_billable_ms, "BIGINT(20) UNSIGNED"
      t.json :runner_properties
      t.string :runner_type, limit: 50, null: false
      t.string :job_check_run_conclusion, limit: 50, null: false
      t.column :organization_id, "BIGINT(20) UNSIGNED", null: false
      t.timestamps precision: 6
    end

    add_index :ghes_actions_job_executions, :event_id, unique: true, name: "index_ghes_actions_job_executions_on_event_id"
    add_index :ghes_actions_job_executions, :created_at, name: "index_ghes_actions_job_executions_on_created_at"
  end
end
