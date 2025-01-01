class RepositoryDependencies2 < ActiveRecord::Migration[5.2]
  def change
    create_table :dg_repository_dependency_arrays, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci" do |t|
      t.integer :github_repository_id, index: true, null: false
      t.mediumblob :dependency_github_ids
      t.mediumblob :transitive_dependency_github_ids
    end
  end
end
