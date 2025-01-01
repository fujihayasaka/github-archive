# typed: true
class ChangeCharsetBypassTable < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::TokenScanningService)

  def up
    change_table(:secret_scanning_push_protections_bypass, bulk: true) do |t|
      t.change :token_type, "varchar(64) CHARACTER SET ascii", null: false, comment: "the type of token that should be allowed into the remotes", collation: "ascii_general_ci"
      t.change :signature, "varchar(64) CHARACTER SET ascii", null: false, comment: "the hex encoded sha256 hash of the raw secret that should be allowed into the remotes", collation: "ascii_general_ci"
    end
  end

  def down
    change_table(:secret_scanning_push_protections_bypass, bulk: true) do |t|
      t.change :token_type, "varchar(64)", null: false, comment: "the type of token that should be allowed into the remotes"
      t.change :signature, "varchar(64)", null: false, comment: "the hex encoded sha256 hash of the raw secret that should be allowed into the remotes"
    end
  end

end
