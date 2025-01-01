# typed: true

class AddFastPathEnabledToCodespacePrebuildConfigurations < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Collab)

  def change
    add_column :codespace_prebuild_configurations, :fast_path_enabled, :boolean, null: false, default: true
  end
end
