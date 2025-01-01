class AddUploadContainerToRepositoryFiles < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::Assets)

  def up
    add_reference :repository_files, :upload_container, polymorphic: true, null: true, type: "BIGINT UNSIGNED", index: false
  end

  def down
    remove_reference :repository_files, :upload_container, polymorphic: true
  end

end
