class CreateRepositorySecurityConfigsTable < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesNotify)

  def change
    create_table :repository_security_configurations, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :security_configuration_id, unsigned: true, null: false
      t.bigint :repository_id, unsigned: true, null: false
      t.integer :state, unsigned: true, null: false

      t.timestamps

      t.index :repository_id, name: "index_repository_security_configurations_repository_id", unique: true
      t.index [:security_configuration_id, :state], name: "index_repository_security_configs_security_config_id_and_state"
    end
  end
end
