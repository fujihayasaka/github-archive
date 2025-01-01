class CreateSecretScanningValidGroupRels < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::TokenScanningService)

  def change
    create_table :secret_scanning_validation_multipart_group_members, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :root_token_scan_result_id, unsigned: true, null: false, comment: "the root (identifying) token scan result id"
      t.bigint :token_scan_result_id, unsigned: true, null: false, comment: "a valid token scan alert id that is participating in the valid (or once valid) tuple"
      t.string :group_id, limit: 128, charset: "ascii", null: false, comment: "comma delimited list of token scan result ids that make up this group. the order of the ids in group_id depends on the order of token types that make up this tuple."

      t.index [:root_token_scan_result_id, :token_scan_result_id, :group_id], unique: true, name: "index_root_result_child_result_group_id", comment: "enforces correctness as a root/child combo can only exist in a group once. also supports fast lookups by root tokens."
      t.index [:token_scan_result_id], name: "index_token_scan_result_id", comment: "supports lookups by non-root tokens"
      t.index [:group_id], name: "index_group_id"
    end
  end
end
