class RepositoriesSha256PreferredFiles < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Repositories)

  def up
    change_table :preferred_files, bulk: true do |t|
      t.change :commit_oid, :string, limit: 64, null: false
    end
  end

  def down
    change_table :preferred_files, bulk: true do |t|
      t.change :commit_oid, :string, limit: 40, null: false
    end
  end
end
