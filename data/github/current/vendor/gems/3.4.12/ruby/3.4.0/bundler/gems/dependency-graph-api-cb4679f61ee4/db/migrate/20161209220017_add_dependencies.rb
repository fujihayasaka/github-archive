class AddDependencies < ActiveRecord::Migration[5.0]
  def change
    create_table :package_dependencies, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci" do |t|
      t.references :dependent
      t.references :depends_on
      t.timestamp :last_specified_at
    end

    add_index(:package_dependencies, [:depends_on_id, :last_specified_at],
      name: :index_pkg_dependencies_depends_on_id_specified_at
    )
    add_index(:package_dependencies, [:depends_on_id, :dependent_id],
      unique: true,
      name: :index_unique_package_dependencies
    )

    create_table :app_dependencies, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci" do |t|
      t.references :dependent
      t.references :depends_on
      t.timestamp :last_specified_at
    end

    add_index :app_dependencies, [:depends_on_id, :last_specified_at]
    add_index(:app_dependencies, [:depends_on_id, :dependent_id],
      unique: true,
      name: :index_unique_app_dependencies
    )
  end
end
