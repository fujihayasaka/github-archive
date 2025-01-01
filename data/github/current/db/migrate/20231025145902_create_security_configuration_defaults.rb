class CreateSecurityConfigurationDefaults < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesNotify)

  def change
    create_table :security_configuration_defaults, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.string :target_type, limit: 30, null: false
      t.bigint :target_id, unsigned: true, null: false
      t.bigint :security_configuration_id, unsigned: true, null: false
      t.boolean :default_for_new_public_repos, default: false, null: false
      t.boolean :default_for_new_private_repos, default: false, null: false
      t.timestamps

      t.index [:target_id, :target_type, :default_for_new_public_repos], name: "index_security_config_defaults_for_new_public_repos_unique", unique: true
      t.index [:target_id, :target_type, :default_for_new_private_repos], name: "index_security_config_defaults_for_new_private_repos_unique", unique: true
      t.index [:security_configuration_id, :target_id, :target_type], name: "index_security_config_defaults_security_config_id_and_target"
    end
  end
end
