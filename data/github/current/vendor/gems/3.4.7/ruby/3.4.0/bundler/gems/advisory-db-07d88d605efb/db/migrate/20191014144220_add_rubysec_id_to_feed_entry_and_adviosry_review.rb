# frozen_string_literal: true

class AddRubysecIDToFeedEntryAndAdviosryReview < ActiveRecord::Migration[5.2]
  # Add support for rubysec Advisories
  # add rubysec_id to FeedEntry and AdvisoryReview
  # Do not in this case case add the id into Advisory
  # This is because the rubysec id is not published publicly, it is internal only
  #
  # I kept the length the same as fophp fields
  def change
    add_column :advisory_reviews, :rubysec_id, :string, limit: 100
    add_index :advisory_reviews, :rubysec_id, unique: true

    add_column :feed_entries, :rubysec_id, :string, limit: 100
    add_index :feed_entries, :rubysec_id
  end
end
