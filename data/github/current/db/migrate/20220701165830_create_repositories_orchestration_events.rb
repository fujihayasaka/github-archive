# typed: true
class CreateRepositoriesOrchestrationEvents < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Repositories)

  def change
    create_table :repository_orchestration_events, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :orchestration_id, unsigned: true, null: false
      t.integer :state, null: false, default: 0
      t.bigint :orchestration_event_subscriber_id, unsigned: true, null: false
      t.timestamps

      t.index [:orchestration_id, :state, :orchestration_event_subscriber_id], name: "index_orchestration_state_subscriber"
      t.index [:updated_at], name: "index_updated_at"
    end
  end
end
