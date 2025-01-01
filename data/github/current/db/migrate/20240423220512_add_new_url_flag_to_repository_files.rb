class AddNewUrlFlagToRepositoryFiles < ActiveRecord::Migration[7.2]
  def change
    change_table :repository_files, bulk: true do |t|
      t.column :using_new_url, :boolean, null: true, default: nil
      t.change :id, :bigint, unsigned: true, null: false, auto_increment: true
      t.change :repository_id, :bigint, unsigned: true, null: false
      t.change :uploader_id, :bigint, unsigned: true, null: false
      t.change :storage_blob_id, :bigint, unsigned: true
    end
  end
end
