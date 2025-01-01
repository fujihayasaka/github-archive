# typed: true
# frozen_string_literal: true

class AddSiteScopedInstallationsTableToLodge < ActiveRecord::Migration[7.2]
  # rubocop:todo GitHub/EnsureDomainIsolationInMigration (can be dropped once table move completed)
  self.use_connection_class(ApplicationRecord::Domain::IntegrationsLodge)

  def change
    # The `site_scoped_integration_installations` table already exists, but we're
    # moving it from `collab` into the `lodge` cluster.
    return if GitHub.enterprise? || GitHub.multi_tenant_enterprise? || Rails.env.production? # rubocop:disable GitHub/DoNotBranchOnRailsEnv

    create_table :site_scoped_integration_installations, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci"  do |t| # rubocop:disable GitHub/UseBigintUnsignedPrimaryKeys
      t.column :integration_id, :bigint, unsigned: true, null: false, index: true

      t.column :target_id,   :bigint,       null: false, unsigned: true
      t.column :target_type, "varchar(25)", null: false

      t.index [:target_id, :target_type], name: :index_site_scoped_integration_installations_on_target

      t.datetime :created_at, precision: nil, null: false, index: true
      t.datetime :updated_at, precision: nil, null: false

      t.column :expires_at, :bigint, index: true
      t.column :rate_limit, :int
    end
  end
end
