class AddDependencyTreeRoot < ActiveRecord::Migration[5.0]
  def change
    create_table :consumer_versions, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci" do |t|
      t.references :consumer, null: false
      t.string :name, index: true
      t.timestamps
    end

    rename_column :dependency_tree_nodes, :root_id, :subtree_id

    create_table :dependency_tree_subtrees, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci" do |t|
      t.timestamps
    end

    create_table :dependency_tree_subtree_dependencies, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci" do |t|
      t.references :dependent, polymorphic: true, null: false, index: false
      t.references :subtree, index: true, null: false
      t.timestamps
    end

    add_index :dependency_tree_subtree_dependencies, [:dependent_type, :dependent_id],
      name: "index_dependency_tree_subtrees_dependent"
  end
end
