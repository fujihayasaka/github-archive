# frozen_string_literal: true

class RenameCVEIDsToCVEs < ActiveRecord::Migration[7.0]
  def change
    rename_table :cve_ids, :cves
  end
end
