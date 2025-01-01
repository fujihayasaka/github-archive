class RemovePackageDeps < ActiveRecord::Migration[5.0]
  def up
    drop_table :package_dependencies
    drop_table :package_dependent_counts
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
