# frozen_string_literal: true

class DropReceivedPushEvents < ActiveRecord::Migration[6.0]
  def up
    drop_table :received_push_events
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          "received_push_events table has been deleted"
  end
end
