# typed: true

class CreateTableSecretScanningExtendedMetadata < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::TokenScanningService)

  def change
    create_table :token_scan_results_metadata, id: false, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column :token_scan_result_id, :bigint, unsigned: true, primary_key: true, auto_increment: false, null: false, default: nil
      t.bigint :repository_id, unsigned: true, null: false
      t.json :metadata, comment: "this is the metadata, it's unencrypted, but internally has encrypted fields"
      t.bigint :github_user_owner_id, unsigned: true, comment: "ID of the github user associated with the owner email found through the provider"
      t.column :owner_email_signature, "varchar(64) CHARACTER SET ascii COLLATE ascii_general_ci", comment: "the hex encoded sha256 sum of the owner_email metadata field"
      t.bigint :encryption_key_hash_id, unsigned: true, null: false,
        comment: "ID of the encryption key last used to encrypt this secret, references secret_scanning_encryption_key_hashes.id"

      t.column :has_owner_email, "TINYINT(1) GENERATED ALWAYS AS (CHAR_LENGTH(COALESCE(JSON_UNQUOTE(JSON_EXTRACT(`metadata`, '$.enc_owner_email')), '')) > 0) VIRTUAL"
      t.column :has_owner_id, "TINYINT(1) GENERATED ALWAYS AS (CHAR_LENGTH(COALESCE(JSON_UNQUOTE(JSON_EXTRACT(`metadata`, '$.enc_owner_id')), '')) > 0) VIRTUAL"
      t.column :has_owner_name, "TINYINT(1) GENERATED ALWAYS AS (CHAR_LENGTH(COALESCE(JSON_UNQUOTE(JSON_EXTRACT(`metadata`, '$.enc_owner_name')), '')) > 0) VIRTUAL"
      t.column :has_secret_id, "TINYINT(1) GENERATED ALWAYS AS (CHAR_LENGTH(COALESCE(JSON_UNQUOTE(JSON_EXTRACT(`metadata`, '$.enc_secret_id')), '')) > 0) VIRTUAL"
      t.column :has_secret_name, "TINYINT(1) GENERATED ALWAYS AS (CHAR_LENGTH(COALESCE(JSON_UNQUOTE(JSON_EXTRACT(`metadata`, '$.enc_secret_name')), '')) > 0) VIRTUAL"
      t.column :has_organization_name, "TINYINT(1) GENERATED ALWAYS AS (CHAR_LENGTH(COALESCE(JSON_UNQUOTE(JSON_EXTRACT(`metadata`, '$.enc_organization_name')), '')) > 0) VIRTUAL"
      t.column :has_organization_id, "TINYINT(1) GENERATED ALWAYS AS (CHAR_LENGTH(COALESCE(JSON_UNQUOTE(JSON_EXTRACT(`metadata`, '$.enc_organization_id')), '')) > 0) VIRTUAL"
      t.column :organization_access, "TINYINT GENERATED ALWAYS AS (JSON_VALUE(`metadata`, '$.organization_access' RETURNING UNSIGNED)) VIRTUAL"
      t.column :secret_issued_date, "DATETIME GENERATED ALWAYS AS (JSON_VALUE(`metadata`, '$.secret_issued_date' RETURNING DATETIME)) VIRTUAL"
      t.column :secret_expiry_date, "DATETIME GENERATED ALWAYS AS (JSON_VALUE(`metadata`, '$.secret_expiry_date' RETURNING DATETIME)) VIRTUAL"
      t.column :secret_last_used_date, "DATETIME GENERATED ALWAYS AS (JSON_VALUE(`metadata`, '$.secret_last_used_date' RETURNING DATETIME)) VIRTUAL"

      t.datetime :created_at, precision: 6, null: false
      t.datetime :updated_at, precision: 6, null: false
      t.datetime :cleared_at, precision: 6,
        comment: "when metadata was cleared for this token scan result because we were not able to get it anymore (e.g. the token was revoked)"
      t.datetime :data_deletion_request_completed_at, precision: 6,
        comment: "when metadata was cleared because of a data deletion request submitted by a user. if this field is NOT NULL then we will no longer get metadata for this token"
      t.datetime :last_checked_at, precision: 6, null: false,
        comment: "when metadata was last checked- not necessarily the same as when it was last updated"

      t.index [
        :repository_id,
        :owner_email_signature,
        :has_owner_email,
        :has_owner_name,
        :has_owner_id,
        :has_secret_name,
        :has_secret_id,
        :has_organization_name,
        :has_organization_id,
        :organization_access,
        :secret_issued_date,
        :secret_expiry_date,
        :secret_last_used_date,
      ], name: "idx_md_fields",
         comment: "covering index on metadata columns. starts with repository_id to support joins from secret scanning repos (or tsr) when querying tokens"
    end
  end
end
