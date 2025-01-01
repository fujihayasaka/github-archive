class AddInitialSchema < ActiveRecord::Migration[5.0]
  def change
    create_table :languages, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci" do |t|
      t.string :name, null: false
      t.timestamps
    end

    create_table :package_managers, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci" do |t|
      t.string :name, null: false
      t.references :language, null: false
      t.timestamps
    end

    create_table :packages, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci" do |t|
      t.string :name, null: false
      t.references :package_manager, index: true, unique: true
      t.timestamps
    end
    add_index :packages, [:package_manager_id, :name], unique: true

    create_table :package_versions, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci" do |t|
      t.references :package, null: false
      t.string :name, index: true
      t.integer :external_id
      t.references :source_host
      t.integer :repository_id, index: true
      t.string :git_ref
      t.boolean :yanked, default: false
      t.timestamps
    end
    add_index :package_versions, [:package_id, :name, :external_id], unique: true

    create_table :dependency_specifications, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci" do |t|
      t.string :version_specification, null: false
      t.references :dependent, null: false
      t.references :depends_on, null: false
      t.references :resolved_to
      t.timestamps
    end
    add_index :dependency_specifications, [:dependent_id, :depends_on_id],
      unique: true, name: "index_dependency_spec_on_dependent_id_and_depends_on_id"

    create_table :source_hosts, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci" do |t|
      t.string :name, null: false
      t.timestamps
    end
  end
end
