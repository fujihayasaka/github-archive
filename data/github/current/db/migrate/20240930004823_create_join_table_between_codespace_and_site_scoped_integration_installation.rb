# typed: true
# frozen_string_literal: true

class CreateJoinTableBetweenCodespaceAndSiteScopedIntegrationInstallation < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::IntegrationsLodge) # rubocop:disable GitHub/EnsureDomainIsolationInMigration

  def change
    create_table :codespaces_site_scoped_integration_installations, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|  # rubocop:disable GitHub/EnsureDomainIsolationInMigration
      t.column :codespace_id, :bigint, unsigned: true, null: false
      t.column :site_scoped_integration_installation_id, :bigint, unsigned: true, null: false
      t.timestamps

      t.index [:codespace_id, :site_scoped_integration_installation_id]
    end
  end
end
