class CreateManifestPackages < ActiveRecord::Migration[7.0]
  def change
    create_table :dg_manifest_packages, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci" do |t|
      t.string :package_name, null: false
      t.integer :package_manager, null: false
      t.timestamps
    end

    add_index :dg_manifest_packages, [:package_manager, :package_name], unique: true,
              name: "index_dg_manifest_packages_on_package_manager_and_package_name"

    create_table :dg_manifest_package_versions, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci" do |t|
      t.references :manifest_package, null: false, index: false
      t.string :requirements, null: false
      t.bigint :encoded_lower_bound
      t.bigint :encoded_upper_bound
      t.timestamps
    end

    add_index :dg_manifest_package_versions, [:manifest_package_id, :requirements], unique: true,
              name: "index_dg_manifest_package_versions_on_package_id_and_reqs"
  end
end
