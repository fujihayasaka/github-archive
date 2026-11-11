# typed: true
# frozen_string_literal: true

class AddIndicesToEPSSFields < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::Vulnerabilities)

  def change
    change_table :cve_epss, bulk: true do |t|
      t.index :percentage, name: "idx_cve_epss_on_percentage"
      t.index :percentile, name: "idx_cve_epss_on_percentile"
    end
  end
end
