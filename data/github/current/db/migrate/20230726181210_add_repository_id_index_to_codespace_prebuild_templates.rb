# typed: true
class AddRepositoryIdIndexToCodespacePrebuildTemplates < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Codespaces)

  def change
    add_index :codespace_prebuild_templates, :repository_id, name: "index_codespace_prebuild_templates_on_repository_id"
  end
end
