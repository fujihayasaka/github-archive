# typed: true
# frozen_string_literal: true

class AddIndexToCodespacesSiteScopedIntegrationInstallations < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::IntegrationsLodge)

  def change
    add_index :codespaces_site_scoped_integration_installations, :site_scoped_integration_installation_id, unique: false
  end
end
