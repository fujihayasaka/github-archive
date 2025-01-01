class ChangePackageVersionIndices < ActiveRecord::Migration[5.0]
  def up
    remove_index :package_versions, [:package_id, :name, :external_id]
    add_index :package_versions, [:package_id, :name], unique: true
    add_index :consumers, [:package_manager, :repository_id], unique: true
    add_index :consumer_versions, [:consumer_id, :name], unique: true
  end

  def down
    remove_index :consumer_versions, [:consumer_id, :name]
    remove_index :consumers, [:package_manager, :repository_id]
    remove_index :package_versions, [:package_id, :name]
    add_index :package_versions, [:package_id, :name, :external_id], unique: true
  end
end
