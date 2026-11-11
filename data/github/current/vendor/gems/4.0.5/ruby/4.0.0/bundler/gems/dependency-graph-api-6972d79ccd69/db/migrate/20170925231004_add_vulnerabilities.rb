class AddVulnerabilities < ActiveRecord::Migration[5.0]
  def change
    create_table :vulnerable_version_ranges, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci" do |t|
      t.integer :github_id, null: false
      t.string :package_name, null: false
      t.string :package_manager, null: false
      t.string :version_range, null: false
      t.bigint :encoded_lower_bound, null: false
      t.bigint :encoded_upper_bound, null: false
      t.timestamps
    end
  end
end
