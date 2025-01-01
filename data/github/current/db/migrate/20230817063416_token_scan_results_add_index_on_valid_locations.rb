# typed: true
class TokenScanResultsAddIndexOnValidLocations < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::TokenScanningService)

  def up
    change_table :token_scan_results, bulk: true do |t|
      t.index [:has_valid_locations, :resolved], unique: false, name: "idx_has_valid_locations_resolved", comment: "support transition for resolving hidden tokens"
    end
  end

  def down
    change_table :token_scan_results, bulk: true do |t|
      t.remove_index name: "idx_has_valid_locations_resolved"
    end
  end
end
