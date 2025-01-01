# frozen_string_literal: true

class AddReviewerIDToCVEReview < ActiveRecord::Migration[5.2]
  def change
    add_column :cve_reviews, :reviewer_id, :integer, null: true
  end
end
