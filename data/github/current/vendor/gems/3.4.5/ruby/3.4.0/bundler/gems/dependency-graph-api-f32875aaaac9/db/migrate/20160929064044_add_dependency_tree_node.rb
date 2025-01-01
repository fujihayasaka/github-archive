class AddDependencyTreeNode < ActiveRecord::Migration[5.0]
  def change
    create_table :dependency_tree_nodes, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci" do |t|
      t.references :root, null: false, index: true
      t.references :descendant, null: false
      t.integer :depth, null: false
      t.timestamps
    end
  end
end
