class AddIndexToRepositories < ActiveRecord::Migration[5.0]
  def change
    add_index :dg_repositories, [:github_repository_id, :public], unique: true
  end
end
