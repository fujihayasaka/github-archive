# typed: true
# frozen_string_literal: true

class AddMemoryDisabledToCopilotSweAgentConfiguration < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Copilot)

  def change
    add_column :copilot_swe_agent_configuration, :memory_disabled, :boolean, null: false, default: false, comment: "Whether agentic memory is disabled for this repository"
  end
end
