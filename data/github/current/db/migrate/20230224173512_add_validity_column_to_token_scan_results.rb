# typed: true

class AddValidityColumnToTokenScanResults < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::TokenScanningService)
  def up
    change_table(:token_scan_results, bulk: true) do |t|
      t.column :validity, "tinyint(3)", null: true, comment: "internal enum/iota within the token-scanning-service representing validity"

      t.index [:token_type, :token_signature], name: "index_token_type_token_signature", comment: "support looking up token scan result by token type and token signature"
      t.index [:repository_id, :has_valid_locations, :validity, :resolution, :token_type, :created_at, :updated_at], name: "index_token_scan_results_on_repo_validity_type_created", comment: "supports filtering by validity"
    end
  end

  def down
    change_table(:token_scan_results, bulk: true) do |t|
      t.remove :validity

      t.remove_index name: "index_token_type_token_signature"
      t.remove_index name: "index_token_scan_results_on_repo_validity_type_created"
    end
  end
end
