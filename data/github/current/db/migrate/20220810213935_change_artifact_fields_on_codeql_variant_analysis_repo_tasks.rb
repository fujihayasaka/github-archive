# typed: false
class ChangeArtifactFieldsOnCodeqlVariantAnalysisRepoTasks < ActiveRecord::Migration[7.1]
  def self.up
    change_table :codeql_variant_analysis_repo_tasks, bulk: true do |t|
      t.remove :artifact_actor
      t.column :artifact_name, :bigint, unsigned: true, null: true
      t.column :artifact_content_type, :string, limit: 100, null: true
    end
  end

  def self.down
    change_table :codeql_variant_analysis_repo_tasks, bulk: true do |t|
      t.column :artifact_actor, :integer, null: true
      t.remove :artifact_name
      t.remove :artifact_content_type
    end
  end
end
