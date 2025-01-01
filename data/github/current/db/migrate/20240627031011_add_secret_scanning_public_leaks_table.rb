# typed: true
# rubocop:disable GitHub/UseBigintUnsignedPrimaryKeys
class AddSecretScanningPublicLeaksTable < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::TokenScanningService)

  def change
    create_table :secret_scanning_public_leaks, id: :false, primary_key: [:token_type, :token_signature], charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column :created_at, "datetime(6)", null: false, comment: "when this record was created"
      t.column :updated_at, "datetime(6)", null: false, comment: "when this record was updated"

      # These two lines are the primary key for the table and match the definitions from token_scan_results
      t.column :token_type, "varchar(64)", charset: "ascii", null: false, comment: "the type of token (from token_scan_results)"
      t.column :token_signature, "varchar(64)", charset: "ascii", null: false, comment: "the hex encoded sha256 checksum of the discovered secret; immutable", collation: "ascii_general_ci"

      # The remaining columns are copied from token_scan_result_locations_v2
      t.column :repository_id, "bigint(20)", unsigned: true, null: false
      t.column :commit_oid, "varbinary(32)", default: nil, comment: "the hex-encoded commit oid that this location was discovered in; sha1 will be 20 chars, while sha256 will be 32"
      t.column :blob_oid, "varbinary(32)", default: nil, comment: "the hex-encoded blob oid that this location was discovered in; sha1 will be 20 chars, while sha256 will be 32"
      t.column :path, "varbinary(1024)", default: nil, comment: "the file path at this location, typically this is some utf8 string but it depends on the git users filesystem encoding"
      t.column :start_line, "int(11)", unsigned: true, default: nil, comment: "if the file, regardless of actual encoding, was read as ascii, this is the number of newline characters encountered before the token was found"
      t.column :end_line, "int(11)", unsigned: true, default: nil, comment: "if the file, regardless of actual encoding, was read as ascii, this is the number of newline characters encountered after reading <start_line> newlines, skipping <start_column> bytes but before reading <end_column> bytes"
      t.column :start_column, "int(11)", unsigned: true, default: nil, comment: "while the column name implies an encoding, one is not implied - this is actually just the explicit number of bytes to read to reach the start of the token, after <start_line> has been reached."
      t.column :end_column, "int(11)", unsigned: true, default: nil, comment: "like start_column, no encoding is applied, this is just the raw number of bytes that should be read after end_line was reached, to include as the secret."
      t.column :content_type, "tinyint(3)", unsigned: true, null: false, default: 0, comment: "the type of content scanned, in which the secret was found in, such as commit, issue, pull request, issue or pull request review comment, discussion etc."
      t.column :content_number, "int(11)", unsigned: true, default: nil, comment: "the number of the content in scope, if applicable"
      t.column :content_id, "bigint(20)", unsigned: true, default: nil, comment: "the ID of the content in scope, if applicable"
    end
  end
end
