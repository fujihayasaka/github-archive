# typed: true

class AddDevContainerAndConfigIdToCodespacePrebuildTemplates < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Collab)

  def change
    change_table(:codespace_prebuild_templates, bulk: true) do |t|
      t.column :codespace_prebuild_configuration_id, :bigint, unsigned: true, null: true
      t.column :devcontainer_path, :string, null: true
    end
  end
end
