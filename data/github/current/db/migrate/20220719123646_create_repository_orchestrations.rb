# typed: true

class CreateRepositoryOrchestrations < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Repositories)

  def change
    create_table :repository_orchestrations, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :repository_id, unsigned: true, null: false
      t.string :type, null: false
      t.integer :state, null: false, default: 0
      t.string :step_name
      t.text :data
      t.integer :attempts, null: false, default: 0
      t.timestamps
    end

    add_index :repository_orchestrations, [:type, :state], unique: false, name: "index_type"
    add_index :repository_orchestrations, [:state, :updated_at], unique: false, name: "index_state_updated_at"
    add_index :repository_orchestrations, [:repository_id, :state, :type], unique: false, name: "index_repository_id"
  end
end
