class AddNameIndexToManifests < ActiveRecord::Migration[5.0]
  def up
    unless index_exists?(:manifests, :name)
      add_index :manifests, :name
    end
  end

  def down
    remove_index :manifests, :name
  end
end
