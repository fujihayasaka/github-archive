# typed: true

class WorkspacesDropGistId < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Collab)

  def up
    change_table(:workspaces, bulk: true) do |t|
      t.remove :gist_id
      t.remove_index [:owner_id, :gist_id]
    end
  end

  def down
    change_table(:workspaces, bulk: true) do |t|
      t.column :gist_id, :bigint, unsigned: true, null: true

      t.index [:owner_id, :gist_id], unique: true
    end
  end
end
