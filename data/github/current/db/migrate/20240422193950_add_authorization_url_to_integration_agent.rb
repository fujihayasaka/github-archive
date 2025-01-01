class AddAuthorizationUrlToIntegrationAgent < ActiveRecord::Migration[7.2]
  use_connection_class ApplicationRecord::Domain::Copilot

  def change
    add_column :integration_agents, :client_authorization_url, :text
  end
end
