class AddOwnerIdToRepositories < ActiveRecord::Migration[5.2]
  def change
    add_column :dg_repositories, :github_owner_id, :integer

    add_index :dg_repositories, :github_owner_id
  end
end
