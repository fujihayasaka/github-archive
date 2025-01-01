# rubocop:disable GitHub/DoNotAddUniqueIndexToExistingColumn
class AddIndexOnSecurityConfigurationDefaults < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesNotify)

  def change
    change_table :security_configuration_defaults, bulk: true do |t|
      t.remove_index [:target_id, :target_type, :default_for_new_public_repos], name: "index_security_config_defaults_for_new_public_repos"
      t.remove_index [:target_id, :target_type, :default_for_new_private_repos], name: "index_security_config_defaults_for_new_private_repos"

      t.index [:target_id, :target_type, :default_for_new_public_repos], unique: true, name: "index_security_config_defaults_for_new_public_repos"
      t.index [:target_id, :target_type, :default_for_new_private_repos], unique: true, name: "index_security_config_defaults_for_new_private_repos"
    end
  end
end
