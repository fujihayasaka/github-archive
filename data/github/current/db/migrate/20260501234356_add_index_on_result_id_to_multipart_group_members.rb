# typed: true

# Adds a non-unique index on `result_id` to support fast lookups by non-root
# result_id (mirrors the existing `index_token_scan_result_id` on the
# deprecated `token_scan_result_id` column). The unique index
# `index_root_result_id_group_id (root_token_scan_result_id, result_id, group_id)`
# does not support `result_id`-only lookups because `result_id` is not the
# leftmost column.
#
# See https://github.com/github/token-scanning-service/pull/8761 for the query
# pattern that needs this index.
class AddIndexOnResultIdToMultipartGroupMembers < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::TokenScanningService)

  def change
    add_index :secret_scanning_validation_multipart_group_members,
      :result_id,
      name: "index_result_id",
      comment: "supports lookups by non-root result_id"
  end
end
