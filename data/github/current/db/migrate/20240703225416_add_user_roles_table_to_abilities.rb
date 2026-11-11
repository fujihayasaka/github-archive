# typed: true
# frozen_string_literal: true

# rubocop:disable GitHub/MigrationCrossSchemaDomainConnection
# rubocop:disable GitHub/EnsureDomainIsolationInMigration

class AddUserRolesTableToAbilities < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::IamAbilities)

  def change
    # The `user_roles` table already exists, but we're moving it
    # from collab into the abilities cluster.
    # rubocop:disable GitHub/DoNotBranchOnRailsEnv
    return if GitHub.enterprise? || GitHub.multi_tenant_enterprise? || Rails.env.production?
    create_table :user_roles, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :role_id, unsigned: true, null: false
      t.bigint :target_id, unsigned: true, null: false
      t.string :target_type, limit: 60, null: false
      t.timestamps
      t.string :actor_type, limit: 60, null: false
      t.bigint :actor_id, unsigned: true, null: false

      t.index [:role_id, :target_id, :target_type, :actor_type, :actor_id], unique: true, name: "index_user_roles_on_role_target_type_actor" # rubocop:disable GitHub/AvoidTypeBeforeId
      t.index [:actor_id, :actor_type, :role_id, :target_id, :target_type], name: "idx_user_roles_actor_role_and_target"
      t.index [:target_id, :target_type], name: "index_user_roles_on_target_id_and_target_type"
      t.index [:role_id, :actor_type, :actor_id], name: "index_user_roles_on_role_id_and_actor_type_and_actor_id" # rubocop:disable GitHub/AvoidTypeBeforeId
      t.index [:actor_id, :actor_type, :target_id, :target_type], name: "index_user_roles_on_actor_and_target"
    end
  end
end
