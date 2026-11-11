# typed: true
# frozen_string_literal: true

class AddCopilotSessionIdIdx < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Copilot)

  def change
    add_index :copilot_agent_sessions, :copilot_session_id
  end
end
