class PrivateRegistryConfigurations < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesNotify)
  def change
    create_table :private_registry_configurations, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      # Owner can be org, repo, user.
      t.string :owner_type, limit: 40, null: false
      t.bigint :owner_id, unsigned: true, null: false

      t.integer :registry_type, limit: 1, unsigned: true, null: false # 1-byte integer for enumeration.
      t.text :url, null: false

      t.string :username, limit: 100
      t.string :secret_name # Does not store actual secrets.

      t.timestamps

      # We expect owner ID and type to be highly cardinal though not completely unique.
      t.index [:owner_id, :owner_type], name: "index_private_registry_configurations_on_owner_id_and_type"
    end
  end
end
