# frozen_string_literal: true

class AddAdvisoryReviewIDToFeedEntry < ActiveRecord::Migration[5.2]
  def change
    add_column :feed_entries, :advisory_review_id, :integer
    add_index :feed_entries, :advisory_review_id
  end
end
