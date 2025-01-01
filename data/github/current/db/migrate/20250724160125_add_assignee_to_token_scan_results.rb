# typed: true

class AddAssigneeToTokenScanResults < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::TokenScanningService)

  def change
    change_table(:token_scan_results, bulk: true) do |t|
      t.column :assigned_owner_scope_id, :bigint, null: true, unsigned: true, comment: "owner_scope.id of the entity to which the token scan result is assigned"

      # Update the ACV filter indexes to include the new assigned_owner_scope_id column
      t.remove_index name: "idx_acv_filters_created"
      t.remove_index name: "idx_acv_filters_updated"

      t.index [:repository_id, :low_confidence, :created_at, :resolved, :publicly_leaked, :internally_leaked, :validity, :token_type, :resolution, :bypass_id, :assigned_owner_scope_id], name: "idx_acv_filters_created", comment: "covering index for all alert-centric-view (ACV) filter-able columns, ordered by created_at"
      t.index [:repository_id, :low_confidence, :updated_at, :resolved, :publicly_leaked, :internally_leaked, :validity, :token_type, :resolution, :bypass_id, :assigned_owner_scope_id], name: "idx_acv_filters_updated", comment: "covering index for all alert-centric-view (ACV) filter-able columns, ordered by updated_at"
    end
  end
end
