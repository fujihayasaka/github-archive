# frozen_string_literal: true

class CreateAutofixSuggestionJobs < ActiveRecord::Migration[7.0]
  def change
    create_table :autofix_suggestion_jobs, charset: "utf8mb4", collation: "utf8mb4_general_ci" do |t|
      t.references :pull_request, null: false, index: false
      t.string :target_sha, null: false, limit: 40
      t.string :rule_sarif_identifier, null: true
      t.json :sarif_content, null: true
      t.timestamps
    end

    add_index :autofix_suggestion_jobs, %i(pull_request_id target_sha), unique: true, name: "index_autofix_suggestion_jobs_on_pull_request_and_sha"
  end
end
