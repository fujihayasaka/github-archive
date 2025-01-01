class NormalizeUtf8Mb4 < ActiveRecord::Migration[6.0]
  def change
    %w(
      dg_abstract_repository_dependencies
      dg_abstract_repository_dependency_counts
      dg_package_release_dependent_counts
      dg_package_release_vuln_counts
      dg_manifest_dependencies
      dg_repositories
    ).each do |table_name|
      execute "ALTER TABLE #{table_name} CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci"
    end
  end
end
