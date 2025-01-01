# typed: true
class AddLockBranchToProtectedBranches < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Repositories)

  def up
    change_table :protected_branches, bulk: true do |t|
      t.column :lock_branch_enforcement_level, :integer, null: false, default: 0
      t.column :lock_allows_fetch_and_merge, :boolean, null: false, default: false
    end

    change_table :archived_protected_branches, bulk: true do |t|
      t.column :lock_branch_enforcement_level, :integer, null: false, default: 0
      t.column :lock_allows_fetch_and_merge, :boolean, null: false, default: false
    end
  end

  def down
    remove_column :protected_branches, :lock_branch_enforcement_level
    remove_column :archived_protected_branches, :lock_branch_enforcement_level
    remove_column :protected_branches, :lock_allows_fetch_and_merge
    remove_column :archived_protected_branches, :lock_allows_fetch_and_merge
  end
end
