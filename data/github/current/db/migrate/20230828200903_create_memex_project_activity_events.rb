class CreateMemexProjectActivityEvents < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Memexes)

  def change
    create_table :memex_project_activity_events, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column :memex_project_id, "bigint(20)", unsigned: true, null: false
      t.column :actor_id, :bigint, unsigned: true, null: true, default: nil
      t.column :memex_project_item_id, :bigint, unsigned: true, null: true, default: nil
      t.json :event, null: false
      t.index [:memex_project_id], name: "index_memex_project_activity_events_on_memex_project_id"
      t.datetime :event_time, null: false, precision: 6
    end
  end
end
