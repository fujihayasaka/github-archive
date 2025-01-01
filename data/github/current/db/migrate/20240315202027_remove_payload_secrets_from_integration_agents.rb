class RemovePayloadSecretsFromIntegrationAgents < ActiveRecord::Migration[7.2]
  use_connection_class ApplicationRecord::Domain::Copilot

  def change
    remove_column :integration_agents, :payload_secret
  end
end
