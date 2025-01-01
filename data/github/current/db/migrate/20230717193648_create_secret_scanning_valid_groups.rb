# typed: true
class CreateSecretScanningValidGroups < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::TokenScanningService)
  def change
    create_table :secret_scanning_validation_multipart_groups, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci", comment: "table that holds metadata related to the validity of sets of tokens that are used together" do |t|
      t.datetime :created_at, null: false, precision: 3, comment: "when this record was created"
      t.string :group_id, limit: 128, charset: "ascii", null: false, comment: "comma delimited list of token scan result ids that make up this group. the order of the ids in group_id depends on the order of token types that make up this tuple."
      t.datetime :last_checked, null: false, precision: 3, comment: "when validity was last checked for this tuple"
      t.datetime :last_checked_active, null: true, precision: 3, comment: "the last time we saw this token tuple was active"
      t.datetime :first_checked_inactive, null: true, precision: 3, comment: "the first time we saw this token tuple was inactive"
      t.bigint :repository_id, unsigned: true, null: false, comment: "the repository this group belongs to"
      t.string :root_token_type, limit: 64, charset: "ascii", null: false, comment: "the token type of the root (or identifying) token for this group"
      t.column :validity, "tinyint(3)", null: false, comment: "internal enum/iota within the token-scanning-service representing validity for this group"

      t.index :group_id, unique: true, name: "index_group_id"
    end
  end
end
