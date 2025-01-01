class UpdateManifestUniqIndex < ActiveRecord::Migration[5.0]
  def up
    unless index_exists?(:manifests, columns)
      add_index :manifests, columns, unique: true, name: :index_unique_manifests
    end
  end

  def down
    if index_exists?(:manifests, columns)
      remove_index :manifests, columns
    end
  end

  private

  def columns
    [:repository_id, :manifest_type, :path, :filename]
  end
end
