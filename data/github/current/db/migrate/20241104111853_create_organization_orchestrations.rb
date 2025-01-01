# typed: true

class CreateOrganizationOrchestrations < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def change
    create_table :organization_orchestrations, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :parent_id, unsigned: true, null: true
      t.bigint :business_id, unsigned: true, null: true
      t.bigint :actor_id, unsigned: true, null: true
      t.string :type, null: false
      t.integer :state, null: false, default: 0
      t.string :step_name
      t.blob :data_organization_ids
      t.blob :data_team_ids
      t.blob :data_user_ids
      t.text :data
      t.integer :attempts, null: false, default: 0
      t.string :error_message, null: true
      t.timestamps

      t.index [:type, :state], unique: false, name: "index_type"
      t.index [:state, :updated_at], unique: false, name: "index_state_updated_at"
      t.index [:parent_id, :state], unique: false, name: "index_parent_id_state"
    end
  end
end
