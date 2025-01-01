class CreateSecurityConfigsTable < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesNotify)

  def change
    create_table :security_configurations, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.string :target_type, limit: 30, null: false
      t.bigint :target_id, unsigned: true, null: false
      t.string :name, limit: 100, null: false
      t.string :description, limit: 255, null: false
      t.boolean :enable_ghas, null: false
      t.integer :private_vulnerability_reporting, unsigned: true, null: false
      t.integer :dependency_graph, unsigned: true, null: false
      t.integer :dependabot_alerts, unsigned: true, null: false
      t.integer :dependabot_security_updates, unsigned: true, null: false
      t.integer :code_scanning, unsigned: true, null: false
      t.integer :secret_scanning, unsigned: true, null: false
      t.integer :secret_scanning_push_protection, unsigned: true, null: false
      t.timestamps

      t.index [:target_id, :target_type], name: "index_security_configurations_target_id_and_target_type"
    end
  end
end
