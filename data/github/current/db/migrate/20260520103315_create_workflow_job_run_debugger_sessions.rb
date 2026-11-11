# typed: true
# frozen_string_literal: true

class CreateWorkflowJobRunDebuggerSessions < ActiveRecord::Migration[8.2]
  use_connection_class(ApplicationRecord::RepositoriesActionsChecks)

  def change
    create_table :workflow_job_run_debugger_sessions, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :workflow_job_run_id, null: false, unsigned: true
      t.bigint :repository_id, null: false, unsigned: true

      t.timestamps

      t.index [:repository_id, :workflow_job_run_id], unique: true
    end

    add_vindex :workflow_job_run_debugger_sessions, :hash, :repository_id
    add_auto_increment :workflow_job_run_debugger_sessions, :id, :workflow_job_run_debugger_sessions_id_seq
  end
end
