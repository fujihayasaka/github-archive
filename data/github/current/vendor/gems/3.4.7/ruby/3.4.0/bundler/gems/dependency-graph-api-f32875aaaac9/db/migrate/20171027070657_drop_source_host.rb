class DropSourceHost < ActiveRecord::Migration[5.0]
  def up
    if table_exists?(:source_hosts)
      drop_table :source_hosts
    end

    if column_exists?(:package_versions, :source_host_id)
      remove_column :package_versions, :source_host_id
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
