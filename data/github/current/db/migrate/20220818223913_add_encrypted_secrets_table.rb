# typed: true

class AddEncryptedSecretsTable < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::TokenScanningService)

  def change
    create_table :secret_scanning_encrypted_secrets, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint    :token_scan_result_id, unsigned: true, null: false, comment: "references token_scan_results.id"
      t.bigint    :encryption_key_hash_id, unsigned: true, null: false, comment: "ID of the encryption key last used to encrypt this secret, references secret_scanning_encryption_key_hashes.id"
      t.blob      :encrypted_secret, null: false, comment: "AES-GCM-256 encrypted bytes for the detected secret, blob has max length of 64kb"

      t.timestamps

      t.index [:token_scan_result_id], name: "index_encrypted_secrets_on_token_scan_result_id", unique: true
      t.index [:encryption_key_hash_id], name: "index_encrypted_secrets_on_encryption_key_hash_id", comment: "allows for efficient re-encryption when rotating keys"
    end
  end
end
