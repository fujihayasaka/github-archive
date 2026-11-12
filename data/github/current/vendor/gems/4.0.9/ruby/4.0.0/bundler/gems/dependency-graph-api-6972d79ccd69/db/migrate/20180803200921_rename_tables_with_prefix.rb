class RenameTablesWithPrefix < ActiveRecord::Migration[5.0]
  PREFIX = "dg_"
  def up
    [:abstract_package_dependencies,
      :abstract_package_dependency_counts,
      :abstract_repository_dependencies,
      :abstract_repository_dependency_counts,
      :checkpoints,
      :dependency_specifications,
      :dependency_tree_subtrees,
      :etl_imports,
      :manifest_dependencies,
      :manifests,
      :package_versions,
      :packages,
      :repositories,
      :star_counts,
      :vulnerable_version_ranges].each do |table|
        rename_table table, "#{PREFIX}#{table}".to_sym
      end
  end

  def down
    [:abstract_package_dependencies,
      :abstract_package_dependency_counts,
      :abstract_repository_dependencies,
      :abstract_repository_dependency_counts,
      :checkpoints,
      :dependency_specifications,
      :dependency_tree_subtrees,
      :etl_imports,
      :manifest_dependencies,
      :manifests,
      :package_versions,
      :packages,
      :repositories,
      :star_counts,
      :vulnerable_version_ranges].each do |table|
        rename_table "#{PREFIX}#{table}".to_sym, table
      end
  end
end
