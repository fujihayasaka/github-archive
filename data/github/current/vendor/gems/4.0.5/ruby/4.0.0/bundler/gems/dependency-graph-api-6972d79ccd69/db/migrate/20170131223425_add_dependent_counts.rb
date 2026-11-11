class AddDependentCounts < ActiveRecord::Migration[5.0]
  def up
    create_table :package_dependent_counts, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci" do |t|
      t.references :depends_on, index: false
      t.integer :dependent_count
    end

    add_index :package_dependent_counts, :depends_on_id, unique: true

    create_table :app_dependent_counts, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci" do |t|
      t.references :depends_on, index: false
      t.integer :dependent_count
    end

    add_index :app_dependent_counts, :depends_on_id, unique: true
  end

  def down
    drop_table :app_dependent_counts
    drop_table :package_dependent_counts
  end
end
