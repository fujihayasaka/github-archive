# typed: true
# frozen_string_literal: true

class MigrateMergeCommitRequestsForSha256 < ActiveRecord::Migration[8.2]
  use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def up
    change_table :merge_commit_requests, bulk: true do |t|
      t.change :merge_sha, "varbinary(32)", null: true
      t.change :rebase_sha, "varbinary(32)", null: true
      t.change :base_branch_sha, "varbinary(32)", null: true
      t.change :head_branch_sha, "varbinary(32)", null: true
    end
  end

  def down
    change_table :merge_commit_requests, bulk: true do |t|
      t.change :merge_sha, "binary(20)", null: true
      t.change :rebase_sha, "binary(20)", null: true
      t.change :base_branch_sha, "binary(20)", null: true
      t.change :head_branch_sha, "binary(20)", null: true
    end
  end
end
