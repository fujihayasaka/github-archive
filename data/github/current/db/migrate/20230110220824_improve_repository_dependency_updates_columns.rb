# typed: true
class ImproveRepositoryDependencyUpdatesColumns < ActiveRecord::Migration[7.1]
  use_connection_class ApplicationRecord::Domain::RepositoriesNotify

  def up
    change_table :repository_dependency_updates, bulk: true do |t|
      t.change :manifest_path, "varbinary(1024)", null: false
      t.change :repository_id, "bigint(20) unsigned", null: false
      t.change :pull_request_id, "bigint(20) unsigned", null: true
      t.change :created_at, "datetime(6)", null: false
      t.change :updated_at, "datetime(6)", null: false
    end
  end

  def down
    change_table :repository_dependency_updates, bulk: true do |t|
      t.change :manifest_path, "varchar(255)", null: false
      t.change :repository_id, "int(11)", null: false
      t.change :pull_request_id, "int(11)", null: true
      t.change :created_at, "datetime", null: false
      t.change :updated_at, "datetime", null: false
    end
  end
end
