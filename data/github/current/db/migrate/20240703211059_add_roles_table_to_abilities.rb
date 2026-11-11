# typed: true
# frozen_string_literal: true

# rubocop:disable GitHub/MigrationCrossSchemaDomainConnection
# rubocop:disable GitHub/EnsureDomainIsolationInMigration

class AddRolesTableToAbilities < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::IamAbilities)

  def change
    # The `roles` table already exists, but we're moving it
    # from collab into the abilities cluster.
    # rubocop:disable GitHub/DoNotBranchOnRailsEnv
    return if GitHub.enterprise? || GitHub.multi_tenant_enterprise? || Rails.env.production?

    create_table :roles, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.binary :name, limit: 255, null: false
      t.bigint :owner_id, unsigned: true, default: nil
      t.string :owner_type, limit: 255, default: nil
      t.timestamps
      t.bigint :base_role_id, unsigned: true, default: nil
      t.binary :description, limit: 608, default: nil
      t.string :target_type, limit: 60, default: nil

      t.index [:name, :owner_id, :owner_type], unique: true, name: "index_roles_on_name_and_owner_id_and_owner_type"
      t.index [:owner_id, :owner_type], name: "index_roles_on_owner_id_and_owner_type"
    end
  end
end
