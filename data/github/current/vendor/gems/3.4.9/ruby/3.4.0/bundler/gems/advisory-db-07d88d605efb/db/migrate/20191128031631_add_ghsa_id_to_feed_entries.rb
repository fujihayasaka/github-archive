# frozen_string_literal: true

class AddGHSAIDToFeedEntries < ActiveRecord::Migration[5.2]
  def change
    add_column :feed_entries, :ghsa_id, :string, limit: 19, null: true
    add_index :feed_entries, :ghsa_id, unique: false
  end
end
