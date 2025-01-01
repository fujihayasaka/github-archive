class ManifestDependencySpecificationsPackageIndex < ActiveRecord::Migration[5.0]
  def up
    unless package_name_index_exists?
      add_index(:manifest_dependency_specifications, :package_name,
        name: :manifest_dep_spec_package_names
      )
    end
  end

  def down
    if package_name_index_exists?
      remove_index :manifest_dependency_specifications, :package_name
    end
  end

  def package_name_index_exists?
    index_exists?(:manifest_dependency_specifications, [:package_name])
  end
end
