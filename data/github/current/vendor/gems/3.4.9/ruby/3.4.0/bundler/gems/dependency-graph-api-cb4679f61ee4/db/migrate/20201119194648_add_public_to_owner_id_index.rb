class AddPublicToOwnerIdIndex < ActiveRecord::Migration[6.0]
  def change
    add_index :dg_repositories, [:github_owner_id, :public]
    remove_index :dg_repositories, :github_owner_id
  end
end
