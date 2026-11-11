# typed: true

class AddSupplementaryDataToMultipartGroupMembers < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::TokenScanningService)

  def change
    # Deprecate token_scan_result_id in favor of result_id (ADR 0150)
    change_column_comment :secret_scanning_validation_multipart_group_members, :token_scan_result_id,
      from: "a valid token scan alert id that is participating in the valid (or once valid) tuple",
      to: "a valid token scan alert id that is participating in the valid (or once valid) tuple - deprecated"

    # Use bulk: true so all column/index additions are done in a single ALTER TABLE on GHES
    change_table :secret_scanning_validation_multipart_group_members, bulk: true do |t|
      # Add result_id: replaces token_scan_result_id, can reference token_scan_results or token_scan_supplementary_results
      t.bigint :result_id, unsigned: true, null: false, default: 0, after: :token_scan_result_id,
        comment: "a valid token scan alert id or token scan supplementary result ID that is participating in the valid (or once valid) tuple"

      # Add is_supplementary: indicates whether result_id references token_scan_supplementary_results
      t.column :is_supplementary, :tinyint, null: false, default: 0, after: :group_id, limit: 1,
        comment: "whether result_id is actually an id from token_scan_supplementary_results"
    end
  end
end
