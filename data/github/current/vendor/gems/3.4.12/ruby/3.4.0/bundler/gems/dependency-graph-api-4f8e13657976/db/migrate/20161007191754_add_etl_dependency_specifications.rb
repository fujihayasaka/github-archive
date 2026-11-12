class AddEtlDependencySpecifications < ActiveRecord::Migration[5.0]
  def change
    create_table :etl_dependency_specs, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci" do |t|
      t.integer :package_manager, null: false
      t.integer :specification_type, null: false
      t.string :dependent_name
      t.string :dependent_version
      t.integer :repository_id
      t.string :git_ref
      t.string :uuid, index: true
      t.timestamps
    end

    create_table :etl_dependency_spec_dependencies, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci" do |t|
      t.references :specification, index: false
      t.string :specification_uuid
      t.string :package_name
      t.string :operator
      t.string :version
      t.integer :scope
      t.timestamps
    end
    add_index :etl_dependency_spec_dependencies, :specification_id,
      name: :index_etl_spec_requirements_spec_id

    rename_table :etl_output_package_version_imports, :etl_imports
    add_column :etl_imports, :stage, :integer
  end
end
