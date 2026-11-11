# frozen_string_literal: true

class AddCWEIDsToCVERequest < ActiveRecord::Migration[6.0]
  def change
    add_column :cve_requests, :cwe_ids, :binary, limit: 255, null: true, default: nil
  end
end
