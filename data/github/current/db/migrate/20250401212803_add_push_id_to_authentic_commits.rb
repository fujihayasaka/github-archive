# typed: true

class AddPushIdToAuthenticCommits < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::RepositoriesPushes)

  def up
    change_table :authentic_commits, bulk: true do |t|
      t.column :push_id, :bigint, unsigned: true, null: true
      t.index :push_id, name: "index_authentic_commits_on_push_id"
    end
    change_column_null :authentic_commits, :verified_at, true
  end

  def down
    change_table :authentic_commits, bulk: true do |t|
      t.remove_index :push_id
      t.remove :push_id
    end
    change_column_null :authentic_commits, :verified_at, false
  end
end
