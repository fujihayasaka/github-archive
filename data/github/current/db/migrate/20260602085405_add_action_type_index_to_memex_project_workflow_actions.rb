# typed: true
# frozen_string_literal: true

class AddActionTypeIndexToMemexProjectWorkflowActions < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Memexes)

  def change
    add_index :memex_project_workflow_actions, [:action_type],
      name: "index_mpwa_on_action_type"
  end
end
