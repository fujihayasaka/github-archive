# typed: true
class AddBillableOwnerIndexToWorkspaces < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Collab)

  def change
    change_table :workspaces, bulk: true do |t|
      t.index [:billable_owner_id, :is_deleted], name: "index_workspaces_on_billable_owner_id_and_is_deleted", unique: false
    end
  end
end
