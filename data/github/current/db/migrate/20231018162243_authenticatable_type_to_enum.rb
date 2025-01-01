# typed: true
# frozen_string_literal: true

class AuthenticatableTypeToEnum < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::IntegrationsLodge)

  def change
    change_table(:authentication_tokens, bulk: true) do |t|
      t.change :authenticatable_type, "enum('IntegrationInstallation', 'ScopedIntegrationInstallation', 'SiteScopedIntegrationInstallation')", null: false
    end
  end
end
