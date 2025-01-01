class AddPackageInfoToDependencySpecification < ActiveRecord::Migration[5.0]
  def up
    add_column :dependency_specifications, :package_manager, :integer
    add_column :dependency_specifications, :package_name, :string, null: false
    change_column :dependency_specifications, :depends_on_id, :integer, null: true
    remove_index :dependency_specifications, [:dependent_id, :depends_on_id]
    add_index :dependency_specifications, [:dependent_id, :package_name], unique: true
  end

  def down
    remove_index :dependency_specifications, [:dependent_id, :package_name]
    add_index :dependency_specifications, [:dependent_id, :depends_on_id],
      unique: true, name: "index_dependency_spec_on_dependent_id_and_depends_on_id"
    remove_column :dependency_specifications, :package_manager
    remove_column :dependency_specifications, :package_name
    change_column :dependency_specifications, :depends_on_id, :integer, null: false
  end
end
