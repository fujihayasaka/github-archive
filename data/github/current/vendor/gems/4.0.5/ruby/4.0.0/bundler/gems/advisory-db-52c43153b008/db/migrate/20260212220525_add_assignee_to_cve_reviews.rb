# frozen_string_literal: true

class AddAssigneeToCVEReviews < ActiveRecord::Migration[8.0]
  def change
    add_column :cve_reviews, :assignee, :string
  end
end
