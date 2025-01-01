class AddPackageLabelToManifestDependency < ActiveRecord::Migration[5.0]
  def change
    add_column :packages, :label, :string
    add_column :dependency_specifications, :package_label, :string
    add_column :manifest_dependencies, :package_label, :string
  end
end
