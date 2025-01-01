# frozen_string_literal: true

class AddReviewRequestedAtToAdvisoryReviews < ActiveRecord::Migration[5.2]
  def change
    add_column :advisory_reviews, :review_requested_at, :datetime
  end
end
