class CreateLowConfidenceIndexesInTokenScanResults < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::TokenScanningService)
  def up
    change_table(:token_scan_results, bulk: true) do |t|
      # Remove a now-redundant index
      t.remove_index [:repository_id, :low_confidence], name: "idx_repo_id_low_confidence"
      # Add new indexes
      t.index [:repository_id, :low_confidence, :resolution, :created_at, :updated_at], name: "idx_tsr_on_repo_low_confidence_resolution_created_updated", comment: "supports filtering by repo, confidence, and resolution"
      t.index [:repository_id, :low_confidence, :resolved, :token_type, :created_at, :updated_at], name: "idx_tsr_on_repo_low_confidence_resolved_type_created", comment: "supports filtering by repo, confidence, resolved, and token type"
      t.index [:repository_id, :low_confidence, :validity, :resolution, :token_type, :created_at, :updated_at], name: "idx_tsr_on_repo_low_confidence_validity_type_created",
      comment: "supports filtering by repo, confidence, validity, and token type"
      t.index [:low_confidence, :resolved], name: "idx_tsr_low_confidence_resolved", comment: "supports filtering by confidence and resolved"
      t.index [:repository_id, :resolution, :created_at, :updated_at], name: "index_token_scan_results_on_repo_resolution_created_updated_2", comment: "supports filtering by resolution"
      t.index [:repository_id, :resolved, :token_type, :created_at, :updated_at], name: "index_token_scan_results_on_repo_resolved_type_created_2", comment: "covering index for both valid locations type and resolved"
      t.index [:repository_id, :validity, :resolution, :token_type, :created_at, :updated_at], name: "index_token_scan_results_on_repo_validity_type_created_2", comment: "supports filtering by validity"
    end

  end

  def down
    change_table(:token_scan_results, bulk: true) do |t|
      t.index [:repository_id, :low_confidence], name: "idx_repo_id_low_confidence", comment: "supports filtering by repo and confidence"

      t.remove_index [:repository_id, :low_confidence, :resolution, :created_at, :updated_at], name: "idx_tsr_on_repo_low_confidence_resolution_created_updated"
      t.remove_index [:repository_id, :low_confidence, :resolved, :token_type, :created_at, :updated_at], name: "idx_tsr_on_repo_low_confidence_resolved_type_created"
      t.remove_index [:repository_id, :low_confidence, :validity, :resolution, :token_type, :created_at, :updated_at], name: "idx_tsr_on_repo_low_confidence_validity_type_created"
      t.remove_index [:low_confidence, :resolved], name: "idx_tsr_low_confidence_resolved"
      t.remove_index [:repository_id, :resolution, :created_at, :updated_at], name: "index_token_scan_results_on_repo_resolution_created_updated_2"
      t.remove_index [:repository_id, :resolved, :token_type, :created_at, :updated_at], name: "index_token_scan_results_on_repo_resolved_type_created_2"
      t.remove_index [:repository_id, :validity, :resolution, :token_type, :created_at, :updated_at], name: "index_token_scan_results_on_repo_validity_type_created_2"
    end
  end
end
