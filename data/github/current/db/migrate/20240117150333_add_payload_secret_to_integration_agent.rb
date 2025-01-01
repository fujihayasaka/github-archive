class AddPayloadSecretToIntegrationAgent < ActiveRecord::Migration[7.2]
  use_connection_class ApplicationRecord::Domain::Copilot

  def change
    add_column :integration_agents, :payload_secret, :text
  end
end
