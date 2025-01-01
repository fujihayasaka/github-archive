# typed: true
# frozen_string_literal: true

class MigrateCVEEPSS < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::Vulnerabilities)
  def change
    create_table :cve_epss, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.string :cve_id, limit: 20, null: false
      t.decimal :percentage, precision: 10, scale: 9, null: false
      t.decimal :percentile, precision: 10, scale: 9, null: false
      t.date :calculation_date, null: false

      t.timestamps
      # Ensures that cve_id values are unique and DB operations involving column are efficient
      t.index [:cve_id], name: "index_cve_epss_on_cve_id", unique: true
    end
  end
end
