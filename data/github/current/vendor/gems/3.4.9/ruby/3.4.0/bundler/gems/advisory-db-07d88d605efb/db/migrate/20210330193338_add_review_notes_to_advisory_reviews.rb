# frozen_string_literal: true

class AddReviewNotesToAdvisoryReviews < ActiveRecord::Migration[6.0]
  def change
    add_column :advisory_reviews, :review_notes, :mediumblob
  end
end
