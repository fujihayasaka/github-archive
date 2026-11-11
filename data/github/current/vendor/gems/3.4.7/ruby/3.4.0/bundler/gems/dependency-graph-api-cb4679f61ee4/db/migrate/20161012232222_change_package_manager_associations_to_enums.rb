class ChangePackageManagerAssociationsToEnums < ActiveRecord::Migration[5.0]
  def up
    drop_table :package_managers
    drop_table :languages
    remove_index :packages, [:package_manager_id, :name]

    remove_column :packages, :package_manager_id
    add_column :packages, :package_manager, :integer, index: true
    add_index :packages, [:package_manager, :name], unique: true

    add_column :packages, :package_pipeline_id, :integer, index: true
    add_column :package_versions, :package_pipeline_id, :integer, index: true

    add_column :packages, :specification_pipeline_id, :integer, index: true
    add_column :package_versions, :specification_pipeline_id, :integer, index: true
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
