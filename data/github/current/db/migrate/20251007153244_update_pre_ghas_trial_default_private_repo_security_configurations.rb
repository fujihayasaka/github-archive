# typed: true

class UpdatePreGhasTrialDefaultPrivateRepoSecurityConfigurations < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::SecurityProductsEnablement)

  def change
    change_table :pre_ghas_trial_default_private_repo_security_configurations, bulk: true do |t|
      # Remove old unique index
      t.remove_index name: "index_target_id_target_type_and_security_configuration_id"

      # Add new unique index that includes sku_name
      # rubocop:disable GitHub/DoNotAddUniqueIndexToExistingColumn
      t.index [:target_id, :target_type, :sku_name, :security_configuration_id], unique: true, name: "index_target_id_target_type_sku_name_security_config_id"
      # rubocop:enable GitHub/DoNotAddUniqueIndexToExistingColumn
    end
  end
end
