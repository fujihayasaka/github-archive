# frozen_string_literal: true

class AddActionsWorkflowRunIdToUpdateJob < ActiveRecord::Migration[6.0]
  def change
    add_column :update_jobs, :actions_external_id, :string, index: true
  end
end
