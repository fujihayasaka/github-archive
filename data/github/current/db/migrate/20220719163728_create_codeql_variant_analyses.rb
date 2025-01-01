# typed: true
class CreateCodeqlVariantAnalyses < ActiveRecord::Migration[7.1]
  def change
    create_table :codeql_variant_analyses, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint  :controller_repo_id,            unsigned: true, null: false
      t.bigint  :actor_id,                      unsigned: true, null: false
      t.string  :query_language,                null: false
      t.text    :query_pack_url,                null: false
      t.bigint  :actions_workflow_run_id,       unsigned: true, null: true
      t.string  :failure_reason,                null: true
      t.integer :over_limit_repo_count,         null: true
      t.text    :over_limit_repo_ids,           null: true
      t.integer :no_codeql_db_repo_count,       null: true
      t.text    :no_codeql_db_repo_ids,         null: true
      t.integer :not_found_repo_count,          null: true
      t.text    :not_found_repo_ids,            null: true
      t.integer :privacy_mismatch_repo_count,   null: true
      t.text    :privacy_mismatch_repo_ids,     null: true

      t.timestamps
    end
  end
end
