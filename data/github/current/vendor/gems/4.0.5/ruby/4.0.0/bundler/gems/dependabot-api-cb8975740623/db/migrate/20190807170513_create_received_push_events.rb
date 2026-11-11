# frozen_string_literal: true

class CreateReceivedPushEvents < ActiveRecord::Migration[6.0]
  def change
    create_table :received_push_events, charset: "utf8mb4", collation: "utf8mb4_general_ci" do |t|
      t.bigint   :repository_id, null: false
      t.string   :ref,           null: false
      t.string   :before_sha,    null: false
      t.string   :after_sha,     null: false
      t.string   :event_source,  null: false
      t.integer  :files_changed, null: false
      t.timestamps

      t.index %i(repository_id after_sha)
    end
  end
end
