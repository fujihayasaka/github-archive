class AddIndexToManifestDependencySpecs < ActiveRecord::Migration[5.0]
  def up
    if former_index_exists?
      remove_index :manifest_dependency_specifications, :package_name
    end

    unless new_index_exists?
      add_index(:manifest_dependency_specifications, columns,
        name: :index_manifest_dep_spec_version_ranges
      )
    end
  end

  def down
    if new_index_exists?
      remove_index :manifest_dependency_specifications, columns
    end

    unless former_index_exists?
      add_index(:manifest_dependency_specifications, :package_name,
        name: :manifest_dep_spec_package_names
      )
    end
  end

  private

  def former_index_exists?
    index_exists?(:manifest_dependency_specifications, [:package_name])
  end

  def new_index_exists?
    index_exists?(:manifest_dependency_specifications, columns)
  end

  def columns
    [:package_name, :encoded_lower_bound, :encoded_upper_bound, :id]
  end
end
