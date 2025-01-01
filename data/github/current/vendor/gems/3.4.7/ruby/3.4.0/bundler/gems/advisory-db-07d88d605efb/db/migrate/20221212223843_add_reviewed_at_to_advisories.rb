# frozen_string_literal: true

class AddReviewedAtToAdvisories < ActiveRecord::Migration[7.0]
  def change
    add_column :advisories, :reviewed_at, :datetime, precision: 6, null: true
  end
end
