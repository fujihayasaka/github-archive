class AddLowConfidenceToTokenScanResults < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::TokenScanningService)
  def up
    change_table(:token_scan_results, bulk: true) do |t|
      t.column :low_confidence, :boolean, null: false, default: false, comment: "whether or not this secret belongs to a low confidence pattern"
      t.index [:repository_id, :low_confidence], name: "idx_repo_id_low_confidence", comment: "supports filtering by repo and confidence"
    end
  end

  def down
    change_table(:token_scan_results, bulk: true) do |t|
      t.remove_index [:repository_id, :low_confidence], name: "idx_repo_id_low_confidence"
      t.remove :low_confidence
    end
  end
end
