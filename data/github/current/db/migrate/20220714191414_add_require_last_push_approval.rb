# typed: true
class AddRequireLastPushApproval < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Repositories)

  def change
    change_table :protected_branches, bulk: true do |t|
      t.column :require_last_push_approval, :boolean, null: false, default: false
    end

    change_table :archived_protected_branches, bulk: true do |t|
      t.column :require_last_push_approval, :boolean, null: false, default: false
    end
  end
end
