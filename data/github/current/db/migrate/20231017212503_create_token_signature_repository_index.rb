class CreateTokenSignatureRepositoryIndex < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::TokenScanningService)

  def up
    change_table(:token_scan_results, bulk: true) do |t|
      t.index [:repository_id, :token_signature], name: "index_token_scan_results_repository_token_signature", comment: "support verifying that a generic secret has not already been discovered in the given repository"
    end
  end

  def down
    change_table(:token_scan_results, bulk: true) do |t|
      t.remove_index [:repository_id, :token_signature], name: "index_token_scan_results_repository_token_signature"
    end
  end
end
