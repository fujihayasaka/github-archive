# frozen_string_literal: true

class AddReviewNotesToCVEReviews < ActiveRecord::Migration[6.1]
  def change
    add_column :cve_reviews, :review_notes, :mediumblob
  end
end
