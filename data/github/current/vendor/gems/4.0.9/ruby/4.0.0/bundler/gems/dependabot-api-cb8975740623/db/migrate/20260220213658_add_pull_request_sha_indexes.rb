# frozen_string_literal: true

class AddPullRequestShaIndexes < ActiveRecord::Migration[7.2]
  def change
    add_index :pull_requests, :dependabot_commit_sha
    add_index :pull_requests, %i(repo_id base_commit_sha)
  end
end
