class AddManifests < ActiveRecord::Migration[5.0]
  def change
    create_table :manifests, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci" do |t|
      t.references :repository
      t.integer :manifest_type, null: false
      t.integer :package_manager, null: false
      t.integer :revision, null: false, default: 0
      t.string :latest_git_ref, null: false
      t.datetime :last_pushed_at, null: false
      t.string :filename
      t.string :path
      t.string :name
      t.timestamps
    end

    add_index :manifests, [:repository_id, :manifest_type, :path], unique: true

    create_table :manifest_dependency_specifications, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci" do |t|
      t.references :manifest, null: false
      t.string :requirements, null: false
      t.string :package_name, null: false
      t.integer :scope, default: 1
      t.bigint :encoded_lower_bound
      t.bigint :encoded_upper_bound
      t.integer :last_seen_at_revision, null: false
      t.timestamps
    end

    add_index(:manifest_dependency_specifications, [:manifest_id, :package_name],
      unique: true,
      name: :manifest_dep_spec_package_name
    )
  end
end
