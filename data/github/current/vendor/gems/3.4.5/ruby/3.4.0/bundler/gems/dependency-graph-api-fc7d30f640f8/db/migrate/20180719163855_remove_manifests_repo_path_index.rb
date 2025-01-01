class RemoveManifestsRepoPathIndex < ActiveRecord::Migration[5.0]
  def up
    remove_index :manifests, [:repository_id, :manifest_type, :path]
    remove_index :manifests, [:repository_id]
  end

  def down
    add_index :manifests, [:repository_id]
    add_index :manifests, [:repository_id, :manifest_type, :path], unique: true
  end
end
