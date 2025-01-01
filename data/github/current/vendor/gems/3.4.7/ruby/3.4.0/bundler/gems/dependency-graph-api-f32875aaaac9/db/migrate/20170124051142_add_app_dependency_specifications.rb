class AddAppDependencySpecifications < ActiveRecord::Migration[5.0]
  def up
    create_table :app_dependency_specifications, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci" do |t|
      t.string :requirements, null: false
      t.integer :dependent_id, null: false
      t.integer :depends_on_id
      t.integer :scope, default: 1
      t.bigint :encoded_lower_bound
      t.bigint :encoded_upper_bound
      t.integer :package_manager
      t.string :package_name, null: false
      t.timestamps
    end

    connection.execute <<-SQL
INSERT app_dependency_specifications (
  requirements,
  dependent_id,
  depends_on_id,
  scope,
  encoded_lower_bound,
  encoded_upper_bound,
  package_manager,
  package_name,
  created_at,
  updated_at
)
SELECT
  requirements,
  dependent_id,
  depends_on_id,
  scope,
  encoded_lower_bound,
  encoded_upper_bound,
  package_manager,
  package_name,
  created_at,
  updated_at
FROM dependency_specifications
WHERE dependent_type = 'ConsumerVersion'
    SQL

    add_index(:app_dependency_specifications, [:dependent_id, :package_name],
      unique: true,
      name: :app_dependency_specs_dependent_id_package_name
    )
    add_index :app_dependency_specifications, :depends_on_id
    add_index :app_dependency_specifications, :package_name
  end

  def down
    remove_index :app_dependency_specifications, :package_name
    remove_index :app_dependency_specifications, :depends_on_id
    remove_index :app_dependency_specifications, [:dependent_id, :package_name]
    drop_table :app_dependency_specifications
  end
end
