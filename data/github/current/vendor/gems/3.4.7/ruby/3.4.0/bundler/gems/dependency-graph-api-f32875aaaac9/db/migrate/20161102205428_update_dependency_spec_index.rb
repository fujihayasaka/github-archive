class UpdateDependencySpecIndex < ActiveRecord::Migration[5.0]
  def up
    remove_index :dependency_specifications, [:dependent_id, :package_name]
    add_index(:dependency_specifications, [:dependent_id, :package_name, :dependent_type],
      unique: true,
      name: "index_dep_spec_on_dependent_id_and_type_and_package_name"
    )
  end

  def down
    remove_index :dependency_specifications, [:dependent_id, :package_name, :dependent_type]
    add_index :dependency_specifications, [:dependent_id, :package_name], unique: true
  end
end
