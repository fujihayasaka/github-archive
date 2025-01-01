class DropArchivedGistReplicas < ActiveRecord::Migration[7.2]
  def change
    drop_table :archived_gist_replicas, if_exists: true
  end
end
