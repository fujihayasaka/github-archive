# frozen_string_literal: true

class AddReviewedAtToAdvisoryReviewsCampaigns < ActiveRecord::Migration[7.0]
  def change
    add_column :advisory_reviews_campaigns, :reviewed_at, :datetime, precision: 6, null: true
  end
end
