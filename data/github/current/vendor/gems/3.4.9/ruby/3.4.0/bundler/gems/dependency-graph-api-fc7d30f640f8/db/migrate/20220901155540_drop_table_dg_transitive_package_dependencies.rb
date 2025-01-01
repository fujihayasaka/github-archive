class DropTableDgTransitivePackageDependencies < ActiveRecord::Migration[6.0]
  def up
    drop_table :dg_transitive_package_dependencies
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
