# typed: true
# frozen_string_literal: true

class AddIndexToCVEEPSSOnUpdatedAt < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::Vulnerabilities)

  def change
    change_table :cve_epss, bulk: true do |t|
      t.index :updated_at, unique: false
    end
  end
end
