class CreateManifestEntries < ActiveRecord::Migration[7.0]
  def change
    create_table :dg_manifest_entries, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci" do |t|
      t.references :manifest, null: false, index: false
      t.references :manifest_package_version, null: false
      t.integer :scope, default: 1, null: false
      t.integer :last_seen_at_revision, null: false
      t.timestamps
    end

    add_index :dg_manifest_entries, [:manifest_id, :manifest_package_version_id], unique: true,
              name: "index_dg_manifest_entries_on_manifest_and_version"
  end
end
