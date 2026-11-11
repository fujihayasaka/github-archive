# typed: true

class CreatePreGhasTrialDefaultPrivateRepoSecurityConfigurations < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::SecurityProductsEnablement)

  def change
    create_table :pre_ghas_trial_default_private_repo_security_configurations, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :security_configuration_id, unsigned: true, null: false
      t.bigint :target_id, unsigned: true, null: false
      t.string :target_type, null: false, limit: 30
      t.bigint :billing_entity_id, unsigned: true, null: false
      t.string :billing_entity_type, null: false, limit: 30
      t.string :sku_name, null: false, limit: 80
      t.integer :trial_type, null: false, unsigned: true, limit: 1
      t.timestamps

      t.index [:billing_entity_id, :billing_entity_type, :sku_name], name: "index_billing_entity_and_sku_name"
      t.index [:target_id, :target_type, :security_configuration_id], unique: true, name: "index_target_id_target_type_and_security_configuration_id"
    end
  end
end
