# frozen_string_literal: true

class CreateAdvisories < ActiveRecord::Migration[5.1]
  def change
    create_table :advisories do |t|
      t.string :identifier, null: false
      t.string :platform
      t.datetime :reported_at
      t.string :title
      t.text :description
      t.string :cvssv2
      t.string :cvssv3
      t.string :severity
      t.string :cpe22
      t.string :cpe23
      t.integer :ingestion_state, null: false, default: 0
      t.string :rejection_reason
      t.integer :relevance_score
      t.text :raw_data, limit: 16.megabytes - 1
      t.string :source
      t.boolean :source_changed, null: false, default: false

      t.index [:identifier], unique: true
      t.timestamps
    end
  end
end
