# frozen_string_literal: true

class CreateGHSLRequests < ActiveRecord::Migration[7.0]
  def change
    create_table :ghsl_requests do |t|
      t.string :ghsa_id, limit: 19, null: false
      t.string :ghsl_id, null: false
      t.string :ghsl_issue, null: false
      t.timestamps
      t.index [:ghsa_id, :ghsl_id, :ghsl_issue], unique: true
    end
  end
end
