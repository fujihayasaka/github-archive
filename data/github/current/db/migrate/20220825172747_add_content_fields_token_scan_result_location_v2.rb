# typed: true

class AddContentFieldsTokenScanResultLocationV2 < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::TokenScanningService)

  def up
    change_table_comment(:token_scan_result_locations_v2, from: "table that holds unique paths for tokens found in token_scan_results, including the location the secret was found at within the file.", to: "table that holds unique paths for tokens found in token_scan_results, including the location the secret was found at.")

    # Change existing commit-based location columns to be nullable
    change_column_null :token_scan_result_locations_v2, :commit_oid, true
    change_column_null :token_scan_result_locations_v2, :blob_oid, true
    change_column_null :token_scan_result_locations_v2, :path, true
    change_column_null :token_scan_result_locations_v2, :start_line, true
    change_column_null :token_scan_result_locations_v2, :end_line, true
    change_column_null :token_scan_result_locations_v2, :start_column, true
    change_column_null :token_scan_result_locations_v2, :end_column, true

    add_column :token_scan_result_locations_v2, :content_type, "tinyint(3)", null: false, unsigned: true, default: 0, comment: "the type of content scanned, in which the secret was found in, such as commit, issue, pull request, issue or pull request review comment, discussion etc."
    add_column :token_scan_result_locations_v2, :content_number, "int(11)", null: true, unsigned: true, comment: "the number of the content in scope, if applicable"
    add_column :token_scan_result_locations_v2, :content_id, "bigint(20)", null: true, unsigned: true, comment: "the ID of the content scanned, if applicable"

    add_index :token_scan_result_locations_v2, [:content_type, :content_number, :content_id], name: "index_token_scan_result_locations_v2_on_content_type_id_number", comment: "for looking up non-code content locations."
  end

  def down
    change_table_comment(:token_scan_result_locations_v2, from: "table that holds unique paths for tokens found in token_scan_results, including the location the secret was found at.", to: "table that holds unique paths for tokens found in token_scan_results, including the location the secret was found at within the file.")

    change_column_null :token_scan_result_locations_v2, :commit_oid, false
    change_column_null :token_scan_result_locations_v2, :commit_oid, false
    change_column_null :token_scan_result_locations_v2, :blob_oid, false
    change_column_null :token_scan_result_locations_v2, :path, false
    change_column_null :token_scan_result_locations_v2, :start_line, false
    change_column_null :token_scan_result_locations_v2, :end_line, false
    change_column_null :token_scan_result_locations_v2, :start_column, false
    change_column_null :token_scan_result_locations_v2, :end_column, false

    remove_column :token_scan_result_locations_v2, :content_type, if_exists: true
    remove_column :token_scan_result_locations_v2, :content_number, if_exists: true
    remove_column :token_scan_result_locations_v2, :content_id, if_exists: true

    remove_index :token_scan_result_locations_v2, name: "index_token_scan_result_locations_v2_on_content_type_id_number", if_exists: true
  end
end
