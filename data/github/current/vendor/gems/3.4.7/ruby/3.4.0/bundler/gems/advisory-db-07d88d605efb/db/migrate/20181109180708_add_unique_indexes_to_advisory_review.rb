# frozen_string_literal: true

class AddUniqueIndexesToAdvisoryReview < ActiveRecord::Migration[5.2]
  def change
    remove_index :advisory_reviews, :cve_id
    add_index :advisory_reviews, :cve_id, unique: true

    remove_index :advisory_reviews, :ghsa_id
    add_index :advisory_reviews, :ghsa_id, unique: true
  end
end
