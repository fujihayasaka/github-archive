# frozen_string_literal: true

class AddWhiteSourceIDToAdvisory < ActiveRecord::Migration[5.2]
  def change
    add_column :advisories, :white_source_id, :string, limit: 40
    add_index :advisories, :white_source_id, unique: true

    add_column :advisory_reviews, :white_source_id, :string, limit: 40
    add_index :advisory_reviews, :white_source_id, unique: true

    add_column :feed_entries, :white_source_id, :string, limit: 40
    add_index :feed_entries, :white_source_id
  end
end
