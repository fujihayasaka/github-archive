# typed: true

class CreateTokenScanSupplementaryResults < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::TokenScanningService)

  def change
    create_table :token_scan_supplementary_results, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci",
      comment: "holds supplementary data used to validate token scan results" do |t|
      t.bigint   :repository_id,    null: false, unsigned: true, comment: "the repository_id that the supplementary result was discovered in; immutable"
      t.datetime :created_at,       null: false, precision: 3
      t.datetime :updated_at,       null: false, precision: 3
      t.column   :type,             "varchar(64) CHARACTER SET ascii COLLATE ascii_general_ci", null: false, comment: "the internal-only supplementary result type; immutable"
      t.column   :signature,         "varchar(64) CHARACTER SET ascii COLLATE ascii_general_ci", null: false, comment: "the hex encoded sha256 checksum of the discovered result; immutable"
      t.bigint   :scan_id,          unsigned: true, comment: "the secret_scanning_scans.id which this record was found in, if any; immutable"
      t.column   :encrypted_result,  "blob", null: false, comment: "AES-GCM-256 encrypted bytes for the supplementary data"
      t.bigint   :encryption_key_hash_id, null: false, unsigned: true, comment: "ID of the encryption key last used to encrypt this result, references secret_scanning_encryption_key_hashes.id"
      t.column   :commit_oid,       "varchar(64) CHARACTER SET ascii COLLATE ascii_general_ci", comment: "the hex-encoded commit oid of the location this result was discovered at; sha1 will be 40 chars, while sha256 will be 64"
      t.column   :blob_oid,         "varchar(64) CHARACTER SET ascii COLLATE ascii_general_ci", comment: "the hex-encoded blob oid at the location for this result; sha1 will be 40 chars, while sha256 will be 64"
      t.column   :path,             "varbinary(1024)", comment: "the file path the result was found in, typically this is some utf8 string but it depends on the git users filesystem encoding"
      t.integer  :start_line,       unsigned: true, comment: "if the file, regardless of actual encoding, was read as ascii, this is the number of newline characters encountered before the result was found"
      t.integer  :end_line,         unsigned: true, comment: "if the file, regardless of actual encoding, was read as ascii, this is the number of newline characters encountered after reading <start_line> newlines, skipping <start_column> bytes but before reading <end_column> bytes"
      t.integer  :start_column,     unsigned: true, comment: "while the column name implies an encoding, one is not implied - this is actually just the explicit number of bytes to read to reach the start of the result, after <start_line> has been reached."
      t.integer  :end_column,       unsigned: true, comment: "like start_column, no encoding is applied, this is just the raw number of bytes that should be read after end_line was reached, to include as the result."
      t.column   :content_type,     "tinyint unsigned", null: false, default: 0, comment: "the type of content scanned, in which the result was found in, such as commit, issue, pull request, issue or pull request review comment, discussion etc."
      t.integer  :content_number,   unsigned: true, comment: "the number of the content in scope, if applicable"
      t.bigint   :content_id,       unsigned: true, comment: "the ID of the content scanned, if applicable"

      t.index [:repository_id, :type, :signature], unique: true, name: "idx_supplementary_results_repo_type_signature"
      t.index [:scan_id], name: "idx_supplementary_results_scan_id", comment: "for looking up records by an explicit scan which created it"
      t.index [:encryption_key_hash_id], name: "idx_supplementary_results_encryption_key_hash_id", comment: "allows for efficient re-encryption when rotating keys"
    end
  end
end
