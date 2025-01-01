class AddUnpublishedAt < ActiveRecord::Migration[5.0]
  def change
    add_column :package_versions, :unpublished_at, :timestamp
  end
end
