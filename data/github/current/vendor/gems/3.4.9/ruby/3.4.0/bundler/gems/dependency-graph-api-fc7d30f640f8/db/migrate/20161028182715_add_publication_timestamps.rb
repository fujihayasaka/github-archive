class AddPublicationTimestamps < ActiveRecord::Migration[5.0]
  def change
    add_column :package_versions, :published_at, :timestamp
    add_column :package_versions, :pushed_at, :timestamp
    add_column :consumer_versions, :pushed_at, :timestamp
  end
end
