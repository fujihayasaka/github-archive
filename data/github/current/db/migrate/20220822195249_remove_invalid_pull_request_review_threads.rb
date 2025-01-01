# typed: true
class RemoveInvalidPullRequestReviewThreads < ActiveRecord::Migration[7.1]
  use_connection_class ApplicationRecord::Domain::IssuesPullRequests


  def up
    return unless GitHub.enterprise?

    connection.execute(<<~SQL)
      DELETE FROM pull_request_review_threads WHERE repository_id = 0;
    SQL
  end

  def down
  end
end
