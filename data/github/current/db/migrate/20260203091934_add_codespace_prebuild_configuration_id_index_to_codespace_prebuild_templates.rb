# typed: true

class AddCodespacePrebuildConfigurationIdIndexToCodespacePrebuildTemplates < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Codespaces)

  def change
    add_index :codespace_prebuild_templates, :codespace_prebuild_configuration_id
  end
end
