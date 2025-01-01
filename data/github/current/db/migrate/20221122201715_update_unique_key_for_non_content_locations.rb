# typed: true
class UpdateUniqueKeyForNonContentLocations < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::TokenScanningService)
  def change
    add_index :token_scan_result_locations_v2, [:token_scan_result_id, :content_type, :content_number, :content_id], unique: true, name: "index_token_scan_result_locations_v2_unique_content_types", comment: "unique constraint for non-code content locations like issues, pull requests, discussion comments, etc."
  end
end
