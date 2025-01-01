# frozen_string_literal: true

class CreateCVEReviewsTable < ActiveRecord::Migration[5.2]
  def change
    create_table :cve_reviews do |t|
      t.string :ghsa_id, limit: 19, null: false

      # which pull request is being used for the review
      t.integer :pull_request_number, default: nil, null: true

      t.integer :decision, default: 0, null: false
      # if rejected, the reason goes here
      t.mediumblob :comment, default: nil, null: true
      # curator fills in CVE ID here, must default to to undefined
      t.string :assigned_cve_id, limit: 40, default: nil, null: true
      # curator fills in the description for the CVE here, if approved
      t.mediumblob :cve_description, default: nil, null: true
      # curator fills in the reference list for the CVE here, if approved
      t.text :cve_references, default: nil, null: true

      t.index [:ghsa_id], unique: true
      t.index [:pull_request_number], unique: true
      t.timestamps
    end
  end
end
