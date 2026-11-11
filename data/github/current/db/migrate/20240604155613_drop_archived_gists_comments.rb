class DropArchivedGistsComments < ActiveRecord::Migration[7.2]
  def change
    drop_table :archived_gist_comments, if_exists: true
  end
end
