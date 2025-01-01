# typed: true
class AddUploadContainerToUserAssets < ActiveRecord::Migration[7.1]
  def up
    add_reference :user_assets, :upload_container, polymorphic: true, null: true, type: "BIGINT(20) UNSIGNED", index: false
  end

  def down
    remove_reference :user_assets, :upload_container, polymorphic: true
  end
end
