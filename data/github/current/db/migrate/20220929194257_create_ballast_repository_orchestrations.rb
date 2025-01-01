# typed: true
class CreateBallastRepositoryOrchestrations < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Ballast)

  def change
    create_table :ballast_orchestrations, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :repository_id, unsigned: true, null: true
      t.string :type, null: false
      t.integer :state, null: false, default: 0
      t.string :step_name
      t.text :data
      t.integer :attempts, null: false, default: 0
      t.bigint :parent_id, unsigned: true, null: true
      t.string :error_message, null: true
      t.timestamps
    end

    add_index :ballast_orchestrations, [:type, :state], unique: false, name: "index_type"
    add_index :ballast_orchestrations, [:state, :updated_at], unique: false, name: "index_state_updated_at"
    add_index :ballast_orchestrations, [:repository_id, :state, :type], unique: false, name: "index_repository_id"
    add_index :ballast_orchestrations, [:updated_at, :state], unique: false, name: "index_updated_at_state"
    add_index :ballast_orchestrations, [:parent_id, :state], unique: false, name: "index_parent_id_state"
  end
end
