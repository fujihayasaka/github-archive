class RemoveUnusedUsersIndices < ActiveRecord::Migration[7.2]
  # These indices are unused per https://github.com/github/search-and-flywheel/issues/453
  def change
    change_table :users, bulk: true do |t|
      t.remove_index :updated_at
      t.remove_index :migration_id
      t.remove_index :pinned_api_version
    end
  end
end
