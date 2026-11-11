# typed: true

class AddScanIdTokenScanResultLocationsV2 < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::TokenScanningService)
  def up
    change_table_comment(:token_scan_result_locations_v2, "table that holds unique paths for tokens found in token_scan_results, including the location the secret was found at within the file.")

    change_table(:token_scan_result_locations_v2, bulk: true) do |t|

      ## change existing columns
      t.change :token_scan_result_id, "bigint(20)", null: false, unsigned: true, comment: "the parent token_scan_results.id for this location"
      t.change :repository_id, "bigint(20)", null: false, unsigned: true, comment: "the repository_id that this location was found in; useful for finding locations without a join through token_scan_results"
      t.change :commit_oid, "varchar(64) CHARACTER SET ascii", null: false, comment: "the hex-encoded commit oid that this location was discovered in; sha1 will be 40 chars, while sha256 will be 64", collation: "ascii_general_ci"
      t.change :blob_oid, "varchar(64) CHARACTER SET ascii", null: false, comment: "the hex-encoded blob oid at this location; sha1 will be 40 chars, while sha256 will be 64", collation: "ascii_general_ci"
      t.change :path, "varbinary(1024)", null: false, comment: "the file path at this location, typically this is some utf8 string but it depends on the git users filesystem encoding"
      t.change :start_line, "int(11)", null: false, unsigned: true, comment: "if the file, regardless of actual encoding, was read as ascii, this is the number of newline characters encountered before the token was found"
      t.change :end_line, "int(11)", null: false, unsigned: true, comment: "if the file, regardless of actual encoding, was read as ascii, this is the number of newline characters encountered after reading <start_line> newlines, skipping <start_column> bytes but before reading <end_column> bytes"
      t.change :start_column, "int(11)", null: false, unsigned: true, comment: "while the column name implies an encoding, one is not implied - this is actually just the explicit number of bytes to read to reach the start of the token, after <start_line> has been reached."
      t.change :end_column, "int(11)", null: false, unsigned: true, comment: "like start_column, no encoding is applied, this is just the raw number of bytes that should be read after end_line was reached, to include as the secret."
      t.change :ignore_token, "tinyint(1) unsigned", null: false, default: 0, comment: "boolean; true if this location should be ignored. This value is set by customers secret-scanning paths-ignore configuration."

      ## New columns
      t.column :scan_id, "bigint(20)", null: true, unsigned: true, comment: "the secret_scanning_scans.id which location was found in, if any"
      t.index [:scan_id], name: "index_token_scan_result_locations_v2_scan_id", comment: "for looking up records by an explicit scan which created it"
    end
  end

  def down
    change_table_comment(:token_scan_result_locations_v2, nil)

    change_table(:token_scan_result_locations_v2, bulk: true) do |t|

      t.change :token_scan_result_id, "bigint(20)", null: false, unsigned: true, comment: nil
      t.change :repository_id, "bigint(20)", null: false, unsigned: true, comment: nil
      t.change :commit_oid, "varchar(40)", null: false, comment: nil
      t.change :blob_oid, "varchar(40)", null: false, comment: nil
      t.change :path, "varbinary(1024)", null: false, comment: nil
      t.change :start_line, "int(11)", null: false, comment: nil
      t.change :end_line, "int(11)", null: false, comment: nil
      t.change :start_column, "int(11)", null: false, comment: nil
      t.change :end_column, "int(11)", null: false, comment: nil
      t.change :ignore_token, "int(11)", null: false, default: 0, comment: nil

      t.remove :scan_id
      t.remove_index name: "index_token_scan_result_locations_v2_scan_id"
    end
  end
end
