# frozen_string_literal: true

class CreateAdvisoryReviews < ActiveRecord::Migration[5.2]
  def change
    create_table :advisory_reviews do |t|
      t.string :ghsa_id, limit: 19, null: false
      t.string :cve_id, limit: 40
      t.integer :pull_request_number, null: false
      t.integer :state, default: 0, limit: 1, null: false
      t.boolean :reviewer_modified, default: false, null: false
      t.text :payload
      t.timestamps
      t.index :ghsa_id
      t.index :cve_id
      t.index :pull_request_number, unique: true
      t.index :state
    end
  end
end
