class DropDependencyTreeSubtrees < ActiveRecord::Migration[5.2]
  # This table is unused
  def change
    drop_table :dg_dependency_tree_subtrees
  end
end
