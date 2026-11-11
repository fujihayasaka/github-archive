# frozen_string_literal: true

class RemoveUnusedPullRequestsIndexes < ActiveRecord::Migration[7.0]
  def change
    remove_index(
      :pull_requests,
      %i(multiple_dependencies base_commit_ci_status dependabot_commit_ci_status repo_id created_at),
      name: "index_compatibility_score"
    )
  end
end
