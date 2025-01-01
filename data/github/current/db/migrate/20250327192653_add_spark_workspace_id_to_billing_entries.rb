# typed: true

class AddSparkWorkspaceIdToBillingEntries < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Codespaces)

  def up
    change_table :codespace_billing_entries, bulk: true do |t|
      t.column :spark_workbench_id, :bigint, unsigned: true, null: true, default: nil, index: true
    end
  end

  def down
    remove_column :codespace_billing_entries, :spark_workbench_id
  end
end
