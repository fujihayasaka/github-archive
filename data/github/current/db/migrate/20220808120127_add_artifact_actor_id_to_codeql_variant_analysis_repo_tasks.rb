# typed: true
class AddArtifactActorIdToCodeqlVariantAnalysisRepoTasks < ActiveRecord::Migration[7.1]
  def change
    add_column :codeql_variant_analysis_repo_tasks, :artifact_actor_id, :bigint, unsigned: true, null: true
  end
end
