# rubocop:disable GitHub/MigrationCrossSchemaDomainConnection

class DropHiddenProfileTimelineEvents < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def up
    drop_table :hidden_profile_timeline_events, if_exists: true
  end

  def down
    create_table :hidden_profile_timeline_events do |t|
      t.integer :event_type, null: false
      t.integer :subject_id
      t.integer :user_id, null: false
      t.datetime :created_at, null: false, precision: 6
      t.index [:user_id, :event_type, :subject_id], name: "index_hidden_profile_timeline_events_on_keys"
      t.index :created_at
    end
  end
end
