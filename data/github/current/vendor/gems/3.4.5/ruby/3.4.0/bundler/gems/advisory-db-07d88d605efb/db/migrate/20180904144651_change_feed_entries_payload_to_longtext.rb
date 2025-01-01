# frozen_string_literal: true

class ChangeFeedEntriesPayloadToLongtext < ActiveRecord::Migration[5.2]
  def up
    change_column :feed_entries, :payload, :longtext
  end

  def down
    change_column :feed_entries, :payload, :text
  end
end
