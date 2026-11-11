# typed: true

# rubocop:disable GitHub/OneTablePerMigration
class ChangeTokenScanResultLocationsV2ContentNumberToBigint < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::TokenScanningService)

  def up
    change_column :token_scan_result_locations_v2, :content_number, :bigint, unsigned: true, null: true,
      comment: "the number of the content in scope, if applicable"
    change_column :secret_scanning_public_leaks, :content_number, :bigint, unsigned: true, null: true,
      comment: "the number of the content in scope, if applicable"
    change_column :token_scan_supplementary_results, :content_number, :bigint, unsigned: true, null: true,
      comment: "the number of the content in scope, if applicable"
  end

  def down
    change_column :token_scan_result_locations_v2, :content_number, :integer, unsigned: true, null: true,
      comment: "the number of the content in scope, if applicable"
    change_column :secret_scanning_public_leaks, :content_number, :integer, unsigned: true, null: true,
      comment: "the number of the content in scope, if applicable"
    change_column :token_scan_supplementary_results, :content_number, :integer, unsigned: true, null: true,
      comment: "the number of the content in scope, if applicable"
  end
end
# rubocop:enable GitHub/OneTablePerMigration
