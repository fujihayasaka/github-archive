class RenameConsumerToApp < ActiveRecord::Migration[5.0]
  def up
    rename_table :consumers, :apps
    rename_table :consumer_versions, :app_versions
    rename_column :app_versions, :consumer_id, :app_id
  end

  def down
    rename_column :app_versions, :app_id, :consumer_id
    rename_table :app_versions, :consumer_versions
    rename_table :apps, :consumers
  end
end
