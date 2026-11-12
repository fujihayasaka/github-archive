class AddRawRequirementsToManifestDependencies < ActiveRecord::Migration[6.0]
  def change
    add_column :dg_manifest_dependencies, :raw_requirements, :string, null: true
  end
end
