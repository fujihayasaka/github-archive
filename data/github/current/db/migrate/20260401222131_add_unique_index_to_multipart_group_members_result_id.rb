# typed: true

# Backfill transition (PR #425110) has set result_id = token_scan_result_id for all existing rows.
# Verified: zero rows with result_id = 0 AND is_supplementary = 0 remain.
# Table is ~60K rows — safe to add unique index.
class AddUniqueIndexToMultipartGroupMembersResultId < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::TokenScanningService)

  def change
    # rubocop:disable GitHub/DoNotAddUniqueIndexToExistingColumn
    add_index :secret_scanning_validation_multipart_group_members,
      [:root_token_scan_result_id, :result_id, :group_id],
      unique: true,
      name: "index_root_result_id_group_id",
      comment: "enforces correctness as a root/child combo can only exist in a group once. also supports fast lookups by root tokens."
    # rubocop:enable GitHub/DoNotAddUniqueIndexToExistingColumn
  end
end
