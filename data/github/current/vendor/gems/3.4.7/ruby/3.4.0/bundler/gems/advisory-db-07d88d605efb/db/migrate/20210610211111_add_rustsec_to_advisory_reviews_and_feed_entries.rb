# frozen_string_literal: true

class AddRustsecToAdvisoryReviewsAndFeedEntries < ActiveRecord::Migration[6.1]
  def change
    add_column :advisory_reviews, :rustsec_id, :string, limit: 100
    add_index :advisory_reviews, :rustsec_id, unique: true

    add_column :feed_entries, :rustsec_id, :string, limit: 100
    add_index :feed_entries, :rustsec_id
  end
end
