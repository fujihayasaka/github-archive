# typed: true
class CreateAuditTokenScanResults < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::TokenScanningService)
  def change
    create_table :audit_token_scan_results, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci", comment: "audit table for token_scan_results; audited columns are columns on token_scan_results that trigger inserts to this table when those columns are updated" do |t|
      t.bigint :token_scan_result_id, null: false, unsigned: true, comment: "token_scan_results.id parent record to which this alert event belongs"
      t.datetime :active_from, null: false, precision: 3, comment: "token_scan_result.updated_at column value before it was moved to this audit table"
      t.column :resolution, "int(11)", null: true, comment: "audited; internal enum/iota within the token-scanning-service representing the resolution (e.g., revoked, false positive)"
      t.bigint :resolver_id, unsigned: true, comment: "audited; if resolution is not null, this represents the github login ID that applied <resolutions>"
      t.datetime :resolved_at, null: true, precision: 3, comment: "audited; if resolution is not null, the timestamp <resolution> was applied by <resolver_id>"
      t.boolean :resolved, null: false, comment: "audited; boolean field based on the <resolution> field above; some non-null resolutions are considered false here (e.g., re-opened)"
      t.bigint :first_location_id, unsigned: true, comment: "audited; the first location_id associated with this token scan result"
      t.boolean :has_valid_locations, null: false, comment: "audited; boolean; this is a performnce-only column useful as an index, which is based on whether first_location_id > 0"
      t.column :resolution_comment, "VARCHAR(280) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_520_ci", null: true, comment: "audited; user-provided comment explaining the resolution status, if any"
      t.index [:token_scan_result_id, :active_from], name: "index_on_token_scan_result_id_and_active_from", comment: "supports queries to get all resolutions for a token scan result and sorting by active_from"
    end
  end
end
