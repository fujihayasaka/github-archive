class AddAbstractPackageDependency < ActiveRecord::Migration[5.0]
  def change
    create_table :abstract_package_dependencies, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci" do |t|
      t.references :dependent
      t.integer :package_manager
      t.string :package_name
      t.timestamps
    end

    add_index(:abstract_package_dependencies, [:package_name, :dependent_id, :package_manager],
      unique: true,
      name: :index_abstract_package_dep_uniq_package
    )
  end
end
