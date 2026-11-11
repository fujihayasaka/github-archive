class DropPackageVersionEtlTables < ActiveRecord::Migration[5.0]
  def up
    drop_table :etl_output_package_versions
    drop_table :etl_output_package_version_dependencies
  end

  def down
    create_table :etl_output_package_version_dependencies, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci" do |t|
      t.integer  :package_version_id
      t.integer  :external_dependent_id
      t.string   :package_name
      t.string   :requirements
      t.integer  :scope
      t.timestamps
    end

    add_index :etl_output_package_version_dependencies, :package_version_id, name: :idx_etl_version_deps_on_package_version_id

    create_table :etl_output_package_versions, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci" do |t|
      t.integer  :package_manager, null: false
      t.string   :package_name,    null: false
      t.string   :package_version, null: false
      t.binary   :description
      t.text     :authors
      t.integer  :download_count
      t.string   :external_id
      t.string   :source_url
      t.string   :home_url
      t.string   :docs_url
      t.datetime :yanked_at
      t.datetime :published_at
      t.timestamps
    end
  end
end
