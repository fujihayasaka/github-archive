# typed: true
# frozen_string_literal: true

class MigratePullRequestsForSha256 < ActiveRecord::Migration[8.2]
  use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def up
    change_table :pull_requests, bulk: true do |t|
      t.change :base_sha, :string, limit: 64, null: true
      t.change :head_sha, :string, limit: 64, null: true
      t.change :merge_commit_sha, :string, limit: 64, null: true
      t.change :base_sha_on_merge, :string, limit: 64, null: true
    end

    change_table :archived_pull_requests, bulk: true do |t|
      t.change :base_sha, :string, limit: 64, null: true
      t.change :head_sha, :string, limit: 64, null: true
      t.change :merge_commit_sha, :string, limit: 64, null: true
      t.change :base_sha_on_merge, :string, limit: 64, null: true
    end
  end

  def down
    change_table :pull_requests, bulk: true do |t|
      t.change :base_sha, :char, limit: 40, null: true
      t.change :head_sha, :char, limit: 40, null: true
      t.change :merge_commit_sha, :char, limit: 40, null: true
      t.change :base_sha_on_merge, :char, limit: 40, null: true
    end

    change_table :archived_pull_requests, bulk: true do |t|
      t.change :base_sha, :char, limit: 40, null: true
      t.change :head_sha, :char, limit: 40, null: true
      t.change :merge_commit_sha, :char, limit: 40, null: true
      t.change :base_sha_on_merge, :char, limit: 40, null: true
    end
  end
end
