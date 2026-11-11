class AddPackageVersionEncodedIndex < ActiveRecord::Migration[5.0]
  def up
    unless index_exists?(:package_versions, [:package_id, :encoded])
      add_index :package_versions, [:package_id, :encoded]
    end
  end

  def down
    if index_exists?(:package_versions, [:package_id, :encoded])
      remove_index :package_versions, [:package_id, :encoded]
    end
  end
end
