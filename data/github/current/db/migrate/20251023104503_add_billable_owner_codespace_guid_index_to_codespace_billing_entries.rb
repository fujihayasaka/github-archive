# typed: true

class AddBillableOwnerCodespaceGuidIndexToCodespaceBillingEntries < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Codespaces)

  def up
    change_table :codespace_billing_entries, bulk: true do |t|
      # Remove redundant indexes before adding the new composite one
      t.remove_index name: "idx_codespace_billing_on_billable_owner"

      # Add new composite index that covers both use cases
      t.index [:billable_owner_id, :billable_owner_type, :codespace_guid], name: "idx_codespace_billing_on_billable_owner_and_guid"
    end
  end

  def down
    change_table :codespace_billing_entries, bulk: true do |t|
      # Remove the composite index
      t.remove_index name: "idx_codespace_billing_on_billable_owner_and_guid"

      # Restore the original indexes
      t.index [:billable_owner_type, :billable_owner_id], name: "idx_codespace_billing_on_billable_owner"
    end
  end
end
