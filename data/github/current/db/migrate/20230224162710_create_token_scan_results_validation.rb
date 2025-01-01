# typed: true

class CreateTokenScanResultsValidation < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::TokenScanningService)
  def change
    create_table :token_scan_results_validation, id: :bigint, default: nil, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci", comment: "table of validation records for token_scan_results, id is the token_scan_result id" do |t|
      t.datetime :last_checked, null: false, precision: 3, comment: "when validity was last checked"
      t.datetime :last_checked_active, null: true, precision: 3, comment: "the last time we saw this token was active"
      t.datetime :first_checked_inactive, null: true, precision: 3, comment: "the first time we saw this token was inactive"
      t.datetime :created_at, null: false, precision: 3, comment: "when this record was created"
      t.string :token_type, limit: 64, charset: "ascii", null: false, comment: "the type of token (from token_scan_results)"

      t.index [:token_type, :last_checked], name: "index_token_type_last_checked"
    end
  end
end
