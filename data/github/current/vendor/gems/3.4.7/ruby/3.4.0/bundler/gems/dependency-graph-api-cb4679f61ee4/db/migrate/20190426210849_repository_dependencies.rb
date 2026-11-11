class RepositoryDependencies < ActiveRecord::Migration[5.2]
  def change
    create_table :dg_repository_repository_dependencies, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci" do |t|
      t.integer :github_repository_id, index: { name: "index_dg_repository_repository_dependencies_on_gh_id" }, null: false
      t.integer :dependency_github_repository_id, index: { name: "index_dg_repository_repository_dependencies_on_dep_id" }, null: false
    end

    create_table :dg_repository_transitive_repository_dependencies, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci" do |t|
      t.integer :github_repository_id, index: { name: "index_dg_repository_transitive_repository_dependencies_on_gh_id" }, null: false
      t.integer :dependency_github_repository_id, index: { name: "index_dg_repository_transitive_repo_dependencies_on_dep_id" }, null: false
    end
  end
end
