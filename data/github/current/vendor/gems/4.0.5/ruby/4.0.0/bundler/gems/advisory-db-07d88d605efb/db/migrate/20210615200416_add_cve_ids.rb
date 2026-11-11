# frozen_string_literal: true

class AddCVEIDs < ActiveRecord::Migration[6.1]
  def change
    create_table :cve_ids do |t|
      t.string :cve_id, limit: 40, null: false
      t.integer :year, limit: 1, null: false
      t.datetime :assigning_at
      t.datetime :assigned_at
      t.timestamps

      t.index :cve_id, unique: true
      t.index [:year, :assigned_at, :assigning_at]
    end
  end
end
