# typed: true
class AddMergeBaseShaToPullRequestReviews < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::IssuesPullRequests)

  def change
    add_column :pull_request_reviews, :merge_base_sha, "char(40)", null: true, default: nil
  end
end
