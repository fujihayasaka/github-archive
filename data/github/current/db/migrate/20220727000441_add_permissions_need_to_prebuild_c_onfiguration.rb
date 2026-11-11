# typed: true

class AddPermissionsNeedToPrebuildCOnfiguration < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Collab)

  def change
    add_column :codespace_prebuild_configurations, :permission_granted, :boolean, null: false, default: true
  end
end
