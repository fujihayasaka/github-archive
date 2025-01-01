# typed: true

class CreateSecretScanningClosureRequestsTable < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::TokenScanningService)

  def change
    create_table :token_scan_result_closure_requests, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :token_scan_result_id, unsigned: true, null: false, comment: "The ID of the token scan result"
      t.bigint :closure_exemption_request_id, unsigned: true, null: false, comment: "The ID of the closure exemption request. Maps to the `exemption_requests` table"

      t.index [:token_scan_result_id], name: "idx_token_scan_result_id", unique: true
    end
  end
end
