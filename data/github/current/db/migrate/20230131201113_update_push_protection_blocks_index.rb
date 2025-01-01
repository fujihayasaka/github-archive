# typed: true
class UpdatePushProtectionBlocksIndex < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::TokenScanningService)

  def up
    change_table(:secret_scanning_push_protection_blocks, bulk: true) do |t|
      t.remove_index name: "idx_repo_actor_type_signature_date"
      t.index [:repository_id, :actor_id, :token_type, :signature, :block_date],
        unique: true,
        name: "idx_repo_actor_type_signature_date",
        comment: "limits it to at most new 1 row inserted a day per (repo, user, token fingerprint)"
    end
  end

  def down
    change_table(:secret_scanning_push_protection_blocks, bulk: true) do |t|
      t.remove_index name: "idx_repo_actor_type_signature_date"
      t.index [:token_type, :repository_id, :block_date, :actor_id, :signature],
        unique: true,
        name: "idx_repo_actor_type_signature_date",
        comment: "limits it to at most new 1 row inserted a day per (repo, user, token fingerprint)"
    end
  end
end
