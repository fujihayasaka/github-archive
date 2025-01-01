# frozen_string_literal: true

class RemoveCVSSV3FromAdvisoryReviewsAndFeedEntries < ActiveRecord::Migration[6.0]
  def change
    remove_column :advisory_reviews, :cvss_v3
    remove_column :feed_entries, :cvss_v3
  end
end
