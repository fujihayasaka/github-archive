# typed: true
# frozen_string_literal: true

# rubocop:disable GitHub/MigrationCrossSchemaDomainConnection
# rubocop:disable GitHub/EnsureDomainIsolationInMigration

class AddRolePermissionsTableToAbilities < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::IamAbilities)

  def change
    # The `role_permissions` table already exists, but we're moving it
    # from collab into the abilities cluster.
    # rubocop:disable GitHub/DoNotBranchOnRailsEnv
    return if GitHub.enterprise? || GitHub.multi_tenant_enterprise? || Rails.env.production?
    create_table :role_permissions, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :role_id, unsigned: true, null: false
      t.bigint :fine_grained_permission_id, unsigned: true, null: true
      t.timestamps
      t.string :action, limit: 60, null: false

      t.index [:fine_grained_permission_id, :role_id], unique: true, name: "index_role_perms_by_role_and_fgp"
      t.index [:role_id, :action], name: "index_role_permissions_on_role_id_and_action"
    end
  end
end
