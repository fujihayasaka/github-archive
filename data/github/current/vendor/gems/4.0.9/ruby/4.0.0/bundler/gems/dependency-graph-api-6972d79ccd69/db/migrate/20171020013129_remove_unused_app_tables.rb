class RemoveUnusedAppTables < ActiveRecord::Migration[5.0]
  def up
    drop_table :app_dependencies
    drop_table :app_dependency_specifications
    drop_table :app_dependent_counts
    drop_table :app_versions
    drop_table :apps
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
