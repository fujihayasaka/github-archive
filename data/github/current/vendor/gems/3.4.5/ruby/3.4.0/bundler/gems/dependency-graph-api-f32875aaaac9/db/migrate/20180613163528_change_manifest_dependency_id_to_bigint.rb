class ChangeManifestDependencyIdToBigint < ActiveRecord::Migration[5.0]
  def up
    execute "ALTER TABLE manifest_dependency_specifications MODIFY COLUMN id bigint(20) NOT NULL AUTO_INCREMENT;"
    rename_table :manifest_dependency_specifications, :manifest_dependencies
  end

  def down
    rename_table :manifest_dependencies, :manifest_dependency_specifications
    execute "ALTER TABLE manifest_dependency_specifications MODIFY COLUMN id int(11) NOT NULL AUTO_INCREMENT;"
  end
end
