# frozen_string_literal: true

class AddIndexOnPullRequestsCompatibilityScore < ActiveRecord::Migration[6.0]
  def change
    add_index :pull_requests, %i(
      multiple_dependencies
      base_commit_ci_status
      dependabot_commit_ci_status
      repo_id
    ), name: "index_compatibility_score"
  end
end
