class RemoveUnusedTables < ActiveRecord::Migration[5.0]
  def up
    drop_table :etl_dependency_spec_dependencies
    drop_table :etl_dependency_specs
  end

  def down
    create_table :etl_dependency_spec_dependencies, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci" do |t|
      t.integer  :specification_id
      t.string   :specification_uuid
      t.string   :package_name
      t.integer  :scope
      t.string   :requirements
      t.timestamps
    end

    add_index(:etl_dependency_spec_dependencies, :specification_id,
      name: "index_etl_spec_requirements_spec_id"
    )

    create_table :etl_dependency_specs, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci" do |t|
      t.integer  :package_manager, null: false
      t.integer  :specification_type, null: false
      t.string   :dependent_name
      t.string   :dependent_version
      t.integer  :repository_id
      t.string   :git_ref
      t.string   :uuid
      t.boolean  :fork, default: false
      t.boolean  :package
      t.datetime :pushed_at
      t.timestamps
    end

    add_index(:etl_dependency_specs, :uuid,
      name: "specification_uuid_index"
    )
  end
end
