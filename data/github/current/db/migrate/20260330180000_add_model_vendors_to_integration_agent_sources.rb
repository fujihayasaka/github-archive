# typed: strict
# frozen_string_literal: true

class AddModelVendorsToIntegrationAgentSources < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Copilot)

  sig { void }
  def change
    add_column :integration_agent_sources, :model_vendors, :text, null: true
  end
end
