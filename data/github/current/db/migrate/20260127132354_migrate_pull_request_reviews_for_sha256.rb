# typed: true
# frozen_string_literal: true

# rubocop:disable GitHub/ArchivedTable

class MigratePullRequestReviewsForSha256 < ActiveRecord::Migration[8.2]
  use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def up
    change_table :pull_request_reviews, bulk: true do |t|
      t.change :head_sha, :string, limit: 64, null: false
      t.change :merge_base_sha, :string, limit: 64, null: true
    end

    change_table :archived_pull_request_reviews, bulk: true do |t|
      t.change :head_sha, :string, limit: 64, null: false
    end
  end

  def down
    change_table :pull_request_reviews, bulk: true do |t|
      t.change :head_sha, :char, limit: 40, null: false
      t.change :merge_base_sha, :char, limit: 40, null: true
    end

    change_table :archived_pull_request_reviews, bulk: true do |t|
      t.change :head_sha, :char, limit: 40, null: false
    end
  end
end
