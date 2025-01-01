# typed: true
# frozen_string_literal: true

class AddAuthorizationDetailsToSiteScopedIntegrationInstallationsInLodge < ActiveRecord::Migration[7.2]
  # rubocop:todo GitHub/EnsureDomainIsolationInMigration (can be dropped once table move completed)
  self.use_connection_class(ApplicationRecord::Domain::IntegrationsLodge)

  def change
    unless column_exists?(:site_scoped_integration_installations, :authorization_details)
      change_table :site_scoped_integration_installations, bulk: true do |t|
        t.column :authorization_details, :json, null: true
      end
    end
  end
end
