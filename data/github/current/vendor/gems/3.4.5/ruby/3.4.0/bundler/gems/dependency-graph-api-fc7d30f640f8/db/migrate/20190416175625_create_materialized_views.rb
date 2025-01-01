class CreateMaterializedViews < ActiveRecord::Migration[5.2]
  def change
    create_table :dg_package_release_dependent_counts, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci" do |t|
      t.integer :github_owner_id, null: false
      t.references :package_release, null: false
      t.integer :count, null: false, default: 0
      t.timestamps
    end
    add_index :dg_package_release_dependent_counts, [:github_owner_id, :package_release_id], name: :index_dg_package_counts, unique: true

    create_table :dg_package_release_vuln_counts, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci" do |t|
      t.references :package_release, null: false, index: { unique: true }
      t.integer :total_count, null: false, default: 0
      t.integer :critical_count, null: false, default: 0
      t.integer :high_count, null: false, default: 0
      t.integer :moderate_count, null: false, default: 0
      t.integer :low_count, null: false, default: 0
      t.timestamps
    end
    add_index :dg_package_release_vuln_counts, [:package_release_id, :total_count], name: :index_dg_package_release_vuln_counts
  end
end
