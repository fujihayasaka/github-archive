class RepositoriesSha256RepositoryBranchRenames < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Repositories)

  def up
    change_table :repository_branch_renames, bulk: true do |t|
      t.change :old_sha, :string, limit: 64
      t.change :id, :bigint, unsigned: true, null: false, auto_increment: true
      t.change :user_id, :bigint, unsigned: true, null: false
      t.change :repository_id, :bigint, unsigned: true, null: false
    end
  end

  def down
    change_table :repository_branch_renames, bulk: true do |t|
      t.change :repository_id, :integer, unsigned: false, null: false
      t.change :user_id, :integer, unsigned: false, null: false
      t.change :id, :integer, unsigned: false, null: false, auto_increment: true
      t.change :old_sha, :string, limit: 40
    end
  end
end
