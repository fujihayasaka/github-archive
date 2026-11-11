# typed: true
# frozen_string_literal: true

class AddUpdateMessageToIntegrationAgentSources < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Copilot)

  def change
    add_column :integration_agent_sources, :update_message, :text, null: true
  end
end
