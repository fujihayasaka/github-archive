class ReorderIndexedColumns < ActiveRecord::Migration[5.0]
  def up
    add_index :packages, [:name, :package_manager], unique: true
    add_index :consumers, [:repository_id, :package_manager], unique: true

    remove_index :packages, [:package_manager, :name]
    remove_index :consumers, [:package_manager, :repository_id]
  end

  def down
    add_index :consumers, [:package_manager, :repository_id], unique: true
    add_index :packages, [:package_manager, :name], unique: true

    remove_index :consumers, [:repository_id, :package_manager]
    remove_index :packages, [:name, :package_manager]
  end
end
