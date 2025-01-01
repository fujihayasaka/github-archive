# typed: true
# rubocop:disable GitHub/DoNotAddUniqueIndexToExistingColumn

class UpdateMergeCommitRequestsEnumsAndTrackingValues < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def up
    change_table :merge_commit_requests, primary_key: [:repository_id, :pull_request_id, :created_at], charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci", bulk: true do |t|
      t.change :merge_state, "enum('conflict', 'created', 'failed', 'reused')", null: false, comment: "internal enum describing the state of the sought or generated merge commit"
      t.change :rebase_state, "enum('conflict', 'created', 'failed', 'ineligible', 'reused', 'skipped')", null: false, comment: "internal enum describing the state of the sought or generated rebase commit"
      t.column :base_branch_sha, "binary(20)", null: true, comment: "sha of the base branch used to generate merge and rebase commits"
      t.column :head_branch_sha, "binary(20)", null: true, comment: "sha of the head branch used to generate merge and rebase commits"
      t.column :requested_at, :datetime, null: false, precision: 6, default: -> { "CURRENT_TIMESTAMP(6)" }
    end
  end

  def down
    change_table :merge_commit_requests, primary_key: [:repository_id, :pull_request_id, :created_at], charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci", bulk: true do |t|
      t.change :merge_state, "tinyint(3)", unsigned: true, null: false, comment: "internal enum describing the state of the sought or generated merge commit"
      t.change :rebase_state, "tinyint(3)", unsigned: true, null: false, comment: "internal enum describing the state of the sought or generated rebase commit"
      t.remove :base_branch_sha
      t.remove :head_branch_sha
      t.remove :requested_at
    end
  end
end
