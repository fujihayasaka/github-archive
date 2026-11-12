class AddEtlOutputPackageVersions < ActiveRecord::Migration[5.0]
  def change
    create_table :etl_output_package_versions, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci" do |t|
      t.integer :package_manager, null: false
      t.string :package_name, null: false
      t.string :package_version, null: false
      t.column :description, :binary, limit: 1.megabyte
      t.text :authors
      t.integer :download_count
      t.string :external_id
      t.string :source_url
      t.string :home_url
      t.string :docs_url
      t.timestamp :yanked_at
      t.timestamps
    end

    create_table :etl_output_package_version_dependencies, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci" do |t|
      t.references :package_version, index: false
      t.integer :external_dependent_id
      t.string :package_name
      t.string :requirements
      t.integer :scope
      t.timestamps
    end

    create_table :etl_output_package_version_imports, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci" do |t|
      t.integer :package_manager
      t.text :metadata
      t.timestamps
    end

    add_index :etl_output_package_version_dependencies, [:package_version_id],
      name: "index_output_package_version_deps_on_package_version_id"
  end
end
