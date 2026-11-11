# frozen_string_literal: true

class AddStateToFeedEntry < ActiveRecord::Migration[5.2]
  def change
    add_column :feed_entries, :resolution_state, :integer, null: false, default: 0

    add_index :feed_entries, :resolution_state
  end
end
