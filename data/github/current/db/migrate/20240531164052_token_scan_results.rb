class TokenScanResults < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::TokenScanningService)
  def up
    change_table(:token_scan_results, bulk: true) do |t|
      t.remove_index name: "index_token_scan_results_on_repo_resolution_created_updated"
      t.remove_index name: "index_token_scan_results_on_repo_resolved_type_created"
      t.remove_index name: "index_token_scan_results_on_repo_validity_type_created"
      t.remove_index name: "idx_has_valid_locations_resolved"
      t.remove_index name: "idx_tsr_on_repo_low_confidence_resolution_created_updated"
      t.remove_index name: "idx_tsr_on_repo_low_confidence_resolved_type_created"
      t.remove_index name: "idx_tsr_on_repo_low_confidence_validity_type_created"
      t.remove_index name: "idx_tsr_low_confidence_resolved"
      t.remove_index name: "index_token_scan_results_on_repo_resolution_created_updated_2"
      t.remove_index name: "index_token_scan_results_on_repo_resolved_type_created_2"
      t.remove_index name: "index_token_scan_results_on_repo_validity_type_created_2"

      # 2 new columns and altered index for cross-repo querying of a token type+sig so we can identify leaks
      # across the corpus of repositories
      t.column :publicly_leaked, "tinyint(1)", null: false, default: 0, unsigned: true, comment: "whether this token has been leaked in a public repository"
      t.column :internally_leaked, "tinyint(1)", null: false, default: 0, unsigned: true, comment: "whether this token has been leaked in another repository within the same owner or enterprise"
      t.remove_index name: "index_token_type_token_signature" # this index is being modified below
      t.index [:token_type, :token_signature, :publicly_leaked, :internally_leaked, :repository_id], name: "index_token_type_token_signature", comment: "support lookup by token type and token signature, with covering values"

      t.index [:repository_id, :low_confidence, :created_at, :resolved, :publicly_leaked, :internally_leaked, :validity, :token_type, :resolution, :bypass_id], name: "idx_acv_filters_created", comment: "covering index for all alert-centric-view (ACV) filter-able columns, ordered by created_at"
      t.index [:repository_id, :low_confidence, :updated_at, :resolved, :publicly_leaked, :internally_leaked, :validity, :token_type, :resolution, :bypass_id], name: "idx_acv_filters_updated", comment: "covering index for all alert-centric-view (ACV) filter-able columns, ordered by updated_at"

    end
  end

  def down
    change_table(:token_scan_results, bulk: true) do |t|
      t.index [:repository_id, :has_valid_locations, :resolution, :created_at, :updated_at], name: "index_token_scan_results_on_repo_resolution_created_updated"
      t.index [:repository_id, :has_valid_locations, :resolved, :token_type, :created_at, :updated_at], name: "index_token_scan_results_on_repo_resolved_type_created", comment: "covering index for both valid locations type and resolved"
      t.index [:repository_id, :has_valid_locations, :validity, :resolution, :token_type, :created_at, :updated_at], name: "index_token_scan_results_on_repo_validity_type_created", comment: "supports filtering by validity"
      t.index [:has_valid_locations, :resolved], name: "idx_has_valid_locations_resolved", comment: "support transition for resolving hidden tokens"
      t.index [:repository_id, :low_confidence, :resolution, :resolution, :created_at, :updated_at], name: "idx_tsr_on_repo_low_confidence_resolution_created_updated", comment: "supports filtering by repo, confidence, and resolution"
      t.index [:repository_id, :low_confidence, :resolved, :token_type, :created_at, :updated_at], name: "idx_tsr_on_repo_low_confidence_resolved_type_created", comment: "supports filtering by repo, confidence, resolved, and token type"
      t.index [:repository_id, :low_confidence, :validity, :resolution, :token_type, :created_at, :updated_at], name: "idx_tsr_on_repo_low_confidence_validity_type_created", comment: "supports filtering by repo, confidence, validity, and token type"
      t.index [:low_confidence, :resolved], name: "idx_tsr_low_confidence_resolved", comment: "supports filtering by confidence and resolved"
      t.index [:repository_id, :resolution, :created_at, :updated_at], name: "index_token_scan_results_on_repo_resolution_created_updated_2", comment: "supports filtering by resolution"
      t.index [:repository_id, :resolved, :token_type, :created_at, :updated_at], name: "index_token_scan_results_on_repo_resolved_type_created_2", comment: "covering index for both valid locations type and resolved"
      t.index [:repository_id, :validity, :resolution, :token_type, :created_at, :updated_at], name: "index_token_scan_results_on_repo_validity_type_created_2", comment: "supports filtering by validity"

      t.remove :publicly_leaked
      t.remove :internally_leaked

      t.remove_index name: "index_token_type_token_signature"
      t.index [:token_type, :token_signature], name: "index_token_type_token_signature", comment: "support looking up token scan result by token type and token signature"

      t.remove_index name: "idx_acv_filters_created"
      t.remove_index name: "idx_acv_filters_updated"

    end
  end
end
