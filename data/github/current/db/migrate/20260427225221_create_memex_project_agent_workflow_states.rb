# typed: true
# frozen_string_literal: true

class CreateMemexProjectAgentWorkflowStates < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Memexes)

  def change
    create_table :memex_project_agent_workflow_states,
      id: false,
      charset: "utf8mb4",
      collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :memex_project_workflow_action_id, null: false, unsigned: true, primary_key: true, auto_increment: false
      t.integer :active_sessions, null: false, default: 0
      t.integer :concurrency_limit, null: false
      t.datetime :created_at, precision: 6, null: false
      t.datetime :updated_at, precision: 6, null: false
    end
  end
end
