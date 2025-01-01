class ChangeUploadManifestFilesIdToBigint < ActiveRecord::Migration[7.2]
  def change
    change_table :upload_manifest_files, bulk: true do |t|
      t.change :id, :bigint, null: false, auto_increment: true
      t.change :upload_manifest_id, :bigint, null: false
      t.change :repository_id, :bigint, null: false
      t.change :uploader_id, :bigint, null: false
      t.change :storage_blob_id, :bigint
    end
  end
end
