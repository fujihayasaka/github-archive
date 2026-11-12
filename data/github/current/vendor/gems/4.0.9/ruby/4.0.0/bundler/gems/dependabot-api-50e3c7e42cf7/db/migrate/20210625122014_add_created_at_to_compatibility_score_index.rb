# frozen_string_literal: true

class AddCreatedAtToCompatibilityScoreIndex < ActiveRecord::Migration[6.0]
  def up
    remove_index :pull_requests, column: %i(
      multiple_dependencies
      base_commit_ci_status
      dependabot_commit_ci_status
      repo_id
    ), name: "index_compatibility_score"

    add_index :pull_requests, %i(
      multiple_dependencies
      base_commit_ci_status
      dependabot_commit_ci_status
      repo_id
      created_at
    ), name: "index_compatibility_score"
  end

  def down
    remove_index :pull_requests, column: %i(
      multiple_dependencies
      base_commit_ci_status
      dependabot_commit_ci_status
      repo_id
      created_at
    ), name: "index_compatibility_score"

    add_index :pull_requests, %i(
      multiple_dependencies
      base_commit_ci_status
      dependabot_commit_ci_status
      repo_id
    ), name: "index_compatibility_score"
  end
end
