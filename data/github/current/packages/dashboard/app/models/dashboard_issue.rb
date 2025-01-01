# typed: true
# frozen_string_literal: true

# An issue displayed on the dashboard above the home feed.
class DashboardIssue
  attr_reader :issue, :latest_comments

  def initialize(issue, latest_comments:)
    @issue = issue
    @latest_comments = latest_comments
  end

  def to_json
    {
      title: issue.title,
      id: issue.id,
      updatedAt: issue.updated_at,
      permalink: issue.permalink,
      commentCount: issue.issue_comments_count,
      comments: latest_comments.map { |comment| { body: comment.body, author: comment.user.display_login } }
    }
    .to_json
  end

  def ==(other)
    self.issue == other.issue
  end
end
