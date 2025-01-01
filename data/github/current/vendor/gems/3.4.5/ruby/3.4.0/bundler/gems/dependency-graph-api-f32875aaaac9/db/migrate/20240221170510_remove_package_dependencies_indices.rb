class RemovePackageDependenciesIndices < ActiveRecord::Migration[7.1]
  def change
    remove_index :dg_dependency_specifications, name: :index_dependency_specifications_on_package_name, column: [:package_name], if_exists: true
  end
end
