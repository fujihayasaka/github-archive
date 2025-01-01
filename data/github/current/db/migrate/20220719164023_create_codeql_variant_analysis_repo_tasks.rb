# typed: true
class CreateCodeqlVariantAnalysisRepoTasks < ActiveRecord::Migration[7.1]
  def change
    create_table :codeql_variant_analysis_repo_tasks, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint  :codeql_variant_analysis_id,     unsigned: true, null: false
      t.bigint  :repository_id,                  unsigned: true, null: false
      t.string  :status,                         null: false
      t.text    :failure_message,                null: true
      t.integer :result_count,                   null: true
      t.string  :database_commit_sha,            null: true
      t.string  :source_location_prefix,         null: true
      t.integer :artifact_size,                  null: true
      t.string  :artifact_guid,                  null: true
      t.integer :artifact_state,                 null: true
      t.integer :artifact_actor,                 null: true

      t.timestamps
    end

    add_index :codeql_variant_analysis_repo_tasks, [:codeql_variant_analysis_id, :repository_id],
      name: :idx_codeql_va_codeql_va_repo_task, unique: true
  end
end
