# typed: true
# frozen_string_literal: true

class AddAutomationAndCommitFieldsToCopilotAgentSessions < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Copilot)

  def change
    change_table :copilot_agent_sessions, bulk: true do |t|
      t.column :automation_id, :string, limit: 64, null: true
      t.column :is_triggered, :boolean, null: false, default: false
      t.column :head_ref, :binary, limit: 255, null: true
      t.column :base_ref, :binary, limit: 255, null: true
    end
  end
end
