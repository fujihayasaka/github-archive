# typed: true

# rubocop:disable GitHub/UseBigintUnsignedPrimaryKeys
class SecretScanningAssessmentResults < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::TokenScanningService)

  def change
    create_table :secret_scanning_assessment_results, primary_key: [:assessment_id, :repository_id], charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint   :assessment_id, null: false, unsigned: true
      t.bigint   :repository_id,                   null: false, unsigned: true
      t.datetime :created_at,                      null: false, precision: 6
      t.integer  :num_unique_secrets,              null: false, unsigned: true, comment: "the number of unique secrets found in the repo"
      t.integer  :num_unique_paths,                null: false, unsigned: true, comment: "the number of unique paths which had secrets in the repo"
      t.json     :token_aggregates,                null: false, comment: "json array of objects which represent the aggregate of unique secrets found per token type"
      t.index   [:repository_id, :created_at], name: "idx_repository_id"
    end
  end
end
