class AddCopilotWorkspaceIdToBillingEntries < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::Codespaces)

  def change
    change_table :codespace_billing_entries, bulk: true do |t|
      t.column :copilot_workspace_id, "char(36)", default: nil, index: true
      t.change :id,                   :bigint, null: false, auto_increment: true
      t.change :billable_owner_id,    :bigint, null: false
      t.change :codespace_owner_id,   :bigint, null: false
      t.change :repository_id,        :bigint
    end
  end
end
