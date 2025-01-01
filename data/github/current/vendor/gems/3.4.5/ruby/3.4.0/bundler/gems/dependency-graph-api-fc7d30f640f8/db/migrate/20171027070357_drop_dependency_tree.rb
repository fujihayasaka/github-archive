class DropDependencyTree < ActiveRecord::Migration[5.0]
  def up
    drop_table :dependency_tree_nodes
    drop_table :dependency_tree_subtree_dependencies
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
