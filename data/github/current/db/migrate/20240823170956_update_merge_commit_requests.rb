# typed: true

# rubocop:disable GitHub/DoNotAddUniqueIndexToExistingColumn

class UpdateMergeCommitRequests < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def up
    change_table :merge_commit_requests, primary_key: [:repository_id, :pull_request_id, :created_at], charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci", bulk: true do |t|
      # Add new columns
      t.column :priority, :integer, null: false, default: 0, comment: "the priority of the request to create a merge commit"
      t.column :base_repository_id, :bigint, unsigned: true, null: false
      t.column :head_repository_id, :bigint, unsigned: true, null: false
      t.column :merge_sha, "binary(20)", null: true, comment: "sha of the created or reused merge commit"
      t.column :merge_state, "tinyint(3)", unsigned: true, null: false, comment: "internal enum describing the state of the sought or generated merge commit"
      t.column :merge_conflict, :blob, null: true
      t.column :rebase_sha, "binary(20)", null: true, comment: "sha of the created or reused commit"
      t.column :rebase_state, "tinyint(3)", unsigned: true, null: false, comment: "internal enum describing the state of the sought or generated rebase commit"
      t.column :rebase_conflict, :blob, null: true
    end
  end

  def down
    change_table :merge_commit_requests, primary_key: [:repository_id, :pull_request_id, :created_at], charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci", bulk: true do |t|
      # Remove unused columns
      t.remove :priority
      t.remove :base_repository_id
      t.remove :head_repository_id
      t.remove :merge_sha
      t.remove :merge_state
      t.remove :merge_conflict
      t.remove :rebase_sha
      t.remove :rebase_state
      t.remove :rebase_conflict
    end
  end
end
