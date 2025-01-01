# typed: true

class AddEnumsAndIndexesToMergeCommitRequests < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def up
    change_table :merge_commit_requests, primary_key: [:repository_id, :pull_request_id, :created_at], charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci", bulk: true do |t|
      t.change :merge_state, "enum('conflict', 'created', 'failed', 'reused', 'delete')", null: false, comment: "internal enum describing the state of the sought or generated merge commit"
      t.change :rebase_state, "enum('conflict', 'created', 'failed', 'ineligible', 'reused', 'skipped', 'delete')", null: false, comment: "internal enum describing the state of the sought or generated rebase commit"

      t.index [:repository_id, :pull_request_id, :base_branch_sha, :head_branch_sha], name: "index_pull_request_merge_commit_request_head_and_base_sha"
    end
  end

  def down
    change_table :merge_commit_requests, primary_key: [:repository_id, :pull_request_id, :created_at], charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci", bulk: true do |t|
      t.change :merge_state, "enum('conflict', 'created', 'failed', 'reused')", null: false, comment: "internal enum describing the state of the sought or generated merge commit"
      t.change :rebase_state, "enum('conflict', 'created', 'failed', 'ineligible', 'reused', 'skipped')", null: false, comment: "internal enum describing the state of the sought or generated rebase commit"
    end

    remove_index :merge_commit_requests, name: "index_pull_request_merge_commit_request_head_and_base_sha"
  end
end
