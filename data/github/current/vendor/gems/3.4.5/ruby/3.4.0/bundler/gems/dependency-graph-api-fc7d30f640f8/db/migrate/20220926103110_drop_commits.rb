class DropCommits < ActiveRecord::Migration[6.0]
  def up
    drop_table :dg_commits
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
