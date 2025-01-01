class AddAbstractDependencyCount < ActiveRecord::Migration[5.0]
  def change
    create_table :abstract_repository_dependency_counts, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci" do |t|
      t.string :package_name, null: false, index: true
      t.integer :package_manager, null: false
      t.integer :dependent_count, default: 0
    end

    add_index(:abstract_repository_dependency_counts, [:package_name, :package_manager],
      name: :index_abstract_repo_dep_count_uniq,
      unique: true
    )
  end
end
