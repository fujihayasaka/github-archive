# rubocop:disable GitHub/DoNotAddUniqueIndexToExistingColumn

class AddEnforcementToSecurityConfigurationDefaults < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesNotify)

  def change
    change_table :security_configuration_defaults, bulk: true do |t|
      t.column :enforcement, :tinyint, unsigned: true, default: 0, null: false
      t.remove_index [:security_configuration_id, :target_id, :target_type], name: "index_security_config_defaults_security_config_id_and_target"
      t.remove_index [:target_id, :target_type, :default_for_new_public_repos], name: "index_security_config_defaults_for_new_public_repos_unique", unique: true
      t.remove_index [:target_id, :target_type, :default_for_new_private_repos], name: "index_security_config_defaults_for_new_private_repos_unique", unique: true

      t.index [:target_id, :target_type, :security_configuration_id], name: "index_security_config_defaults_target_and_security_config_id", unique: true
      t.index [:target_id, :target_type, :default_for_new_public_repos], name: "index_security_config_defaults_for_new_public_repos"
      t.index [:target_id, :target_type, :default_for_new_private_repos], name: "index_security_config_defaults_for_new_private_repos"
    end
  end
end
