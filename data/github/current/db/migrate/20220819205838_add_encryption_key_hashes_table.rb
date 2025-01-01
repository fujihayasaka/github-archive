# typed: true
class AddEncryptionKeyHashesTable < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::TokenScanningService)

  def change
    create_table :secret_scanning_encryption_key_hashes, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column :hash, "varchar(256)", null: false, comment: "SHA256 hash of an encryption key"

      t.timestamps

      t.index [:hash], name: "index_encryption_key_hashes_on_hash", unique: true
    end
  end
end
