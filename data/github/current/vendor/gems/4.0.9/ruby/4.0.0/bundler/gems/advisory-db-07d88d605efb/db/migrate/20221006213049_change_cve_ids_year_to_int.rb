# frozen_string_literal: true

class ChangeCVEIDsYearToInt < ActiveRecord::Migration[7.0]
  def up
    change_column :cve_ids, :year, :integer, limit: 2, null: false
  end

  def down
    change_column :cve_ids, :year, :integer, limit: 1, null: false
  end
end
