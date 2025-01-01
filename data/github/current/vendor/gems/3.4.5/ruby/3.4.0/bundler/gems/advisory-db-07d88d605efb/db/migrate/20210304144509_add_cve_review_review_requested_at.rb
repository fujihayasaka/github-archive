# frozen_string_literal: true

class AddCVEReviewReviewRequestedAt < ActiveRecord::Migration[6.0]
  def change
    add_column :cve_reviews, :review_requested_at, :datetime
  end
end
