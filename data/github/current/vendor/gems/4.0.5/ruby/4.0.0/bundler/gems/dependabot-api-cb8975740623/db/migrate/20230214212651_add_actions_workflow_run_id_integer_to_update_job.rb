# frozen_string_literal: true

class AddActionsWorkflowRunIdIntegerToUpdateJob < ActiveRecord::Migration[7.0]
  def change
    add_column :update_jobs, :actions_workflow_run_id, :integer, limit: 8
    add_index :update_jobs, :actions_workflow_run_id, unique: true
  end
end
