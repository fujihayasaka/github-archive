class CreateEntityProblems < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Spokes)

  def change
    create_table :entity_problems, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :repository_id, unsigned: true, null: false
      t.column :repository_type, :tinyint, unsigned: true, null: false
      t.bigint :network_id, unsigned: true, null: false
      t.column :priority, :tinyint, unsigned: true, null: false
      t.string :task_name, null: false, limit: 25
      t.column :state, :tinyint, unsigned: true, default: 0

      t.timestamps

      t.index [:repository_id, :repository_type, :network_id], unique: true, name: "index_on_repository_id_repository_type_and_network_id"
      t.index [:priority, :updated_at, :id, :state], name: "index_on_priority_updated_at_id_state"
      t.index [:priority, :created_at], name: "index_on_priority_created_at"
    end
  end
end
