# typed: true
class AddIsDeletedAndIndexToCodespaces < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Collab)

  def change
    change_table :workspaces, bulk: true do |t|
      t.virtual :is_deleted, type: "tinyint(1)", as: "deleted_at IS NOT NULL", null: false

      t.index [:owner_id, :is_deleted, :id, :repository_id], name: :index_workspaces_owner_id_is_deleted_id_repository_id
    end
  end
end
