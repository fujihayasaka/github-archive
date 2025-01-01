# typed: true

class CreateRepositoryPolicyConfigurations < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Repositories)

  def change
    create_table :repository_policy_configurations, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.json :parameters
      t.column :pattern, "varbinary(1024)"
      t.string :policy_type, limit: 100, null: false
      t.bigint :source_id, unsigned: true, null: false
      t.string :source_type, limit: 100, null: false
      t.column :target, "tinyint(3)", unsigned: true, null: false
      t.timestamps

      t.index [:source_id, :source_type, :target], name: "index_policy_configurations_source_and_target"
    end
  end
end
