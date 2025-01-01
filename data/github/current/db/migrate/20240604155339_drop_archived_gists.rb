class DropArchivedGists < ActiveRecord::Migration[7.2]
  def change
    drop_table :archived_gists, if_exists: true
  end
end
