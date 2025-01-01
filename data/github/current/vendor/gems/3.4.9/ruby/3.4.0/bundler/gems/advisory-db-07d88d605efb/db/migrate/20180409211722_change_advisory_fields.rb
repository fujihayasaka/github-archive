# frozen_string_literal: true

class ChangeAdvisoryFields < ActiveRecord::Migration[5.1]
  def change
    change_table :advisories do |t|
      t.remove :reported_at
      t.remove :cpe22
      t.remove :cpe23
      t.change :source, :integer, null: false, default: 0
      t.change :severity, :integer, null: false, default: 0
      t.change :cvssv2, :decimal, precision: 3, scale: 1
      t.change :cvssv3, :decimal, precision: 3, scale: 1
      t.text :cpe22_uris
      t.text :cpe23_uris
      t.text :references
      t.datetime :published_date
      t.datetime :last_modified_date
    end
  end
end
