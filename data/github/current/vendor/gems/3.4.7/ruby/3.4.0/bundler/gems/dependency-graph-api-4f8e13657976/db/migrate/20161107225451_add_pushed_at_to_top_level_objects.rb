class AddPushedAtToTopLevelObjects < ActiveRecord::Migration[5.0]
  def change
    add_column :consumers, :last_published_at, :timestamp
    add_index :consumers, [:last_published_at]
    add_column :packages, :last_published_at, :timestamp
    add_index :packages, [:last_published_at]
  end
end
