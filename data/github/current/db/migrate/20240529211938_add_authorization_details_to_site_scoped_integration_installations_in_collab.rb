# typed: true
# frozen_string_literal: true

class AddAuthorizationDetailsToSiteScopedIntegrationInstallationsInCollab < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::IntegrationsCollab)

  def change
    change_table :site_scoped_integration_installations, bulk: true do |t|
      t.column :authorization_details, :json, null: true
    end
  end
end
