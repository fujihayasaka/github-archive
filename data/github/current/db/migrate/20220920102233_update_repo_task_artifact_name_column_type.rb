# typed: true
class UpdateRepoTaskArtifactNameColumnType < ActiveRecord::Migration[7.1]
  def up
    change_column :codeql_variant_analysis_repo_tasks, :artifact_name, "varchar(255) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL"
  end

  def down
    change_column :codeql_variant_analysis_repo_tasks, :artifact_name, "bigint(20) unsigned DEFAULT NULL"
  end
end
