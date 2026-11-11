# typed: true

class AddScanScopeToAcvIndexes < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::TokenScanningService)

  def change
    change_table(:token_scan_results, bulk: true) do |t|
      # Remove existing ACV indexes
      t.remove_index name: "idx_acv_filters_created", column: [:repository_id, :low_confidence, :created_at, :resolved, :publicly_leaked, :internally_leaked, :validity, :token_type, :resolution, :bypass_id, :assigned_owner_scope_id, :security_campaign_id]
      t.remove_index name: "idx_acv_filters_updated", column: [:repository_id, :low_confidence, :updated_at, :resolved, :publicly_leaked, :internally_leaked, :validity, :token_type, :resolution, :bypass_id, :assigned_owner_scope_id, :security_campaign_id]

      # Recreate with scan_scope appended for efficient scan_type filtering
      t.index [:repository_id, :low_confidence, :created_at, :resolved, :publicly_leaked, :internally_leaked, :validity, :token_type, :resolution, :bypass_id, :assigned_owner_scope_id, :security_campaign_id, :scan_scope], name: "idx_acv_filters_created", comment: "covering index for all alert-centric-view (ACV) filter-able columns, ordered by created_at"
      t.index [:repository_id, :low_confidence, :updated_at, :resolved, :publicly_leaked, :internally_leaked, :validity, :token_type, :resolution, :bypass_id, :assigned_owner_scope_id, :security_campaign_id, :scan_scope], name: "idx_acv_filters_updated", comment: "covering index for all alert-centric-view (ACV) filter-able columns, ordered by updated_at"
    end
  end
end
