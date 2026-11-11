class AddAbstractDependencies < ActiveRecord::Migration[5.0]
  def change
    create_table :abstract_repository_dependencies, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci" do |t|
      t.references :repository, index: true, null: false
      t.integer :package_manager, null: false
      t.string :package_name, null: false
      t.timestamps
    end

    add_index(:abstract_repository_dependencies, [:package_name, :repository_id, :package_manager],
      unique: true,
      name:  :index_abstract_repo_dep_uniq_package
    )
  end
end
