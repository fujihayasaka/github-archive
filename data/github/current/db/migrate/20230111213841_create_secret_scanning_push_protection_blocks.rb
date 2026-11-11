# typed: true

class CreateSecretScanningPushProtectionBlocks < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::TokenScanningService)

  def change
    create_table :secret_scanning_push_protection_blocks, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci", comment: "aggregates the total number of blocks by repo, actor, token type, signature, and block_date" do |t|
      t.bigint :repository_id, unsigned: true, null: false, comment: "id for the repository where the block occurred"
      t.bigint :actor_id, unsigned: true, null: false, comment: "id for the actor/user that triggered the block"
      t.column :token_type, "varchar(64) CHARACTER SET ascii", null: false, comment: "the type of token that was blocked"
      t.column :signature, "varchar(64) CHARACTER SET ascii", null: false, comment: "the hex encoded sha256 hash of the raw secret that was blocked"
      t.date :block_date, null: false, comment: "the day the block occurred on"
      t.datetime :first_blocked_timestamp, precision: 6, null: false,  comment: "timestamp for the first blocked push"
      t.datetime :last_blocked_timestamp, precision: 6, null: false,  comment: "timestamp for the latest blocked push"
      t.bigint :block_count, unsigned: true, null: false, default: 1, comment: "total number of blocks aggregated by repo, actor, token type, signature, and block_date"
    end

    add_index :secret_scanning_push_protection_blocks, [:token_type, :repository_id, :block_date, :actor_id, :signature],
      unique: true,
      name: "idx_repo_actor_type_signature_date",
      comment: "limits it to at most new 1 row inserted a day per (repo, user, token fingerprint)"

  end
end
