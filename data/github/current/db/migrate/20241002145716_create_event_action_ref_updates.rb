# typed: true
# frozen_string_literal: true

class CreateEventActionRefUpdates < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::Repositories)
  def change
    create_table :event_action_ref_updates, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :repository_id, unsigned: true, null: false
      t.column :ref_name, "varbinary(1024)", null: false
      t.string :before_oid, limit: 40
      t.string :after_oid, limit: 40
      t.string :policy_oid, limit: 40
      t.timestamps

      t.index [:repository_id, :ref_name, :before_oid, :after_oid, :policy_oid], name: "index_event_action_ref_update"
    end
  end
end
