class AddLookupIndexesToAbstractDependencies < ActiveRecord::Migration[5.0]
  def up
    unless index_exists?(:abstract_repository_dependencies, columns_to_index)
      add_index(:abstract_repository_dependencies, columns_to_index,
        name: :abstract_repo_dep_lookups
      )
    end

    unless index_exists?(:abstract_package_dependencies, columns_to_index)
      add_index(:abstract_package_dependencies, columns_to_index,
        name: :abstract_package_dep_lookups
      )
    end
  end

  def down
    if index_exists?(:abstract_package_dependencies, columns_to_index)
      remove_index :abstract_package_dependencies, columns_to_index
    end

    if index_exists?(:abstract_repository_dependencies, columns_to_index)
      remove_index :abstract_repository_dependencies, columns_to_index
    end
  end

  def columns_to_index
    [:package_name, :package_manager, :id]
  end
end
