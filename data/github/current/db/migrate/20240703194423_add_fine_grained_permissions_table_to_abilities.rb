# typed: true
# frozen_string_literal: true

# rubocop:disable GitHub/MigrationCrossSchemaDomainConnection
# rubocop:disable GitHub/EnsureDomainIsolationInMigration

class AddFineGrainedPermissionsTableToAbilities < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::IamAbilities)

  def change
    # The `fine_grained_permissions` table already exists, but we're moving it
    # from collab into the abilities cluster.
    # rubocop:disable GitHub/DoNotBranchOnRailsEnv
    return if GitHub.enterprise? || GitHub.multi_tenant_enterprise? || Rails.env.production?

    create_table :fine_grained_permissions, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.string :action, limit: 255, null: false
      t.timestamps
      t.column :custom_roles_enabled, "tinyint(1)", null: false, default: 0
      t.string :target_type, limit: 60, default: nil

      t.index :action, unique: true, name: "index_fine_grained_permissions_on_action"
      t.index :custom_roles_enabled, name: "index_fine_grained_permissions_on_custom_roles_enabled"
    end
  end
end
