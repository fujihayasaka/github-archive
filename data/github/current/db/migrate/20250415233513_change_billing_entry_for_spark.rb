# typed: true

class ChangeBillingEntryForSpark < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Codespaces)

  def up
    change_table :codespace_billing_entries, bulk: true do |t|
      t.remove :spark_workbench_id
      t.column :linked_resources, :json, null: true
    end
  end

  def down
    change_table :codespace_billing_entries, bulk: true do |t|
      t.remove :linked_resources
      t.column :spark_workbench_id, :bigint, unsigned: true, null: true, default: nil, index: true
    end
  end
end
