class CreateSecurityConfigurationPolicies < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesNotify)

  def change
    create_table :security_configuration_policies, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.string :target_type, limit: 30, null: false
      t.bigint :target_id, unsigned: true, null: false
      t.bigint :security_configuration_id, unsigned: true, null: false
      t.column :enforcement, :tinyint, unsigned: true, default: 0, null: false
      t.timestamps

      t.index [:security_configuration_id, :target_id, :target_type], name: "index_security_config_policies_config_id_and_target_unique", unique: true
    end
  end
end
