# typed: true

class AddAssigneeToAuditTokenScanResults < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::TokenScanningService)

  def change
    change_table(:audit_token_scan_results, bulk: true) do |t|
      t.column :assigned_owner_scope_id, :bigint, null: true, unsigned: true, comment: "owner_scope.id of the entity to which the token scan result is assigned"
    end
  end
end
