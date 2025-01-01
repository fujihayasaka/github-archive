# frozen_string_literal: true

class AddStateToCVEReview < ActiveRecord::Migration[5.2]
  def change
    add_column :cve_reviews, :state, :integer, null: false, default: 0
    add_index  :cve_reviews, :state, unique: false
  end
end
