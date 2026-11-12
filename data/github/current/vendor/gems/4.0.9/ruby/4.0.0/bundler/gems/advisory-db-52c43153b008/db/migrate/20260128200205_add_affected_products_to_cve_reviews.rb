# frozen_string_literal: true

class AddAffectedProductsToCVEReviews < ActiveRecord::Migration[8.0]
  def change
    # Add a new column to store multiple affected products as JSON
    # Each entry will be a hash with: vendor, product, and versions (array of objects)
    # Example: [{ "vendor": "w8tcha", "product": "CKEditor", "versions": [{ "version": "< 1.17.12", "status": "affected" }] }]
    add_column :cve_reviews, :affected_products, :json, null: true, default: nil
  end
end
