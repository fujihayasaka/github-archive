class CleanupTransitiveDeps < ActiveRecord::Migration[5.2]
  def change
    drop_table :dg_repository_repository_dependencies
    drop_table :dg_repository_transitive_repository_dependencies
    drop_table :dg_repository_dependency_arrays
  end
end
