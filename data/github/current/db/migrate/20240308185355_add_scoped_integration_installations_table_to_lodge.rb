# typed: true
# frozen_string_literal: true

class AddScopedIntegrationInstallationsTableToLodge < ActiveRecord::Migration[7.2]
  # rubocop:todo GitHub/EnsureDomainIsolationInMigration (can be dropped once table move completed)
  self.use_connection_class(ApplicationRecord::Domain::IntegrationsLodge)

  def change
    # The `scoped_integration_installations` table already exists, but we're
    # moving it from `collab` into the `lodge` cluster.
    return if GitHub.enterprise? || GitHub.multi_tenant_enterprise? || Rails.env.production? # rubocop:disable GitHub/DoNotBranchOnRailsEnv

    create_table :scoped_integration_installations, id: :bigint, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t| # rubocop:disable GitHub/UseBigintUnsignedPrimaryKeys
      t.column :integration_installation_id, :bigint, null: false # rubocop:disable GitHub/ReferencingColumnsMustBeBigint
      t.index :integration_installation_id, name: :index_scoped_installations_on_integration_installation_id

      t.datetime :created_at, precision: nil, null: false, index: true
      t.datetime :updated_at, precision: nil, null: false

      t.column :expires_at,            :bigint, index: true
      t.column :authorization_details, :json
    end
  end
end
