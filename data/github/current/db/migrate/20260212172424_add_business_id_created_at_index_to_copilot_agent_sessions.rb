# typed: true
# frozen_string_literal: true

class AddBusinessIdCreatedAtIndexToCopilotAgentSessions < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Copilot)

  def change
    add_index :copilot_agent_sessions, [:business_id, :created_at], name: "index_copilot_agent_sessions_on_business_id_created_at"
  end
end
