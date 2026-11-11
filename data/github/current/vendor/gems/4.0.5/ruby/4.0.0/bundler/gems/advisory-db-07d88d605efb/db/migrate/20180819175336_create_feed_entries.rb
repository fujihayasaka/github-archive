# frozen_string_literal: true

class CreateFeedEntries < ActiveRecord::Migration[5.2]
  def change
    create_table :feed_entries do |t|
      t.integer :source, null: false
      t.string :identifier, null: false
      t.string :cve_id, limit: 40
      t.text :payload
      t.text :review_payload
      t.timestamps
      t.index :source
      t.index :identifier, unique: true
      t.index :cve_id
    end
  end
end
