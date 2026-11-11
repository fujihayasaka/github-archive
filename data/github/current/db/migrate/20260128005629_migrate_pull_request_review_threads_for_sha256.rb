# typed: true
# frozen_string_literal: true

# rubocop:disable GitHub/ExistingIdColumnsMustBeBigint

class MigratePullRequestReviewThreadsForSha256 < ActiveRecord::Migration[8.2]
  use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def up
    change_table :pull_request_review_threads, bulk: true do |t|
      t.change :commit_id, :string, limit: 64, null: true
      t.change :original_commit_id, :string, limit: 64, null: true
      t.change :original_base_commit_id, :string, limit: 64, null: true
      t.change :original_start_commit_id, :string, limit: 64, null: true
      t.change :original_end_commit_id, :string, limit: 64, null: true
      t.change :blob_commit_oid, :string, limit: 64, null: true
    end

    change_table :archived_pull_request_review_threads, bulk: true do |t|
      t.change :commit_id, :string, limit: 64, null: true
      t.change :original_commit_id, :string, limit: 64, null: true
      t.change :original_base_commit_id, :string, limit: 64, null: true
      t.change :original_start_commit_id, :string, limit: 64, null: true
      t.change :original_end_commit_id, :string, limit: 64, null: true
      t.change :blob_commit_oid, :string, limit: 64, null: true
    end
  end

  def down
    change_table :pull_request_review_threads, bulk: true do |t|
      t.change :commit_id, :char, limit: 40, null: true
      t.change :original_commit_id, :char, limit: 40, null: true
      t.change :original_base_commit_id, :char, limit: 40, null: true
      t.change :original_start_commit_id, :char, limit: 40, null: true
      t.change :original_end_commit_id, :char, limit: 40, null: true
      t.change :blob_commit_oid, :char, limit: 40, null: true
    end

    change_table :archived_pull_request_review_threads, bulk: true do |t|
      t.change :commit_id, :char, limit: 40, null: true
      t.change :original_commit_id, :char, limit: 40, null: true
      t.change :original_base_commit_id, :char, limit: 40, null: true
      t.change :original_start_commit_id, :char, limit: 40, null: true
      t.change :original_end_commit_id, :char, limit: 40, null: true
      t.change :blob_commit_oid, :char, limit: 40, null: true
    end
  end
end
