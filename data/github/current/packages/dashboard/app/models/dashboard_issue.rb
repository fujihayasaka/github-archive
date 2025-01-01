# typed: true
# frozen_string_literal: true

# An issue displayed on the dashboard above the home feed.
class DashboardIssue
  attr_reader :issue

  def initialize(issue)
    @issue = issue
  end

  def to_h
    {
      author: issue.user.display_login,
      title: issue.title,
      id: issue.id,
      number: issue.number,
      updatedAt: issue.updated_at,
      permalink: issue.permalink,
      commentCount: issue.issue_comments_count,
      repoNameWithOwner: {
        name: issue.repository.name,
        ownerLogin: issue.repository.owner.display_login,
      },
      readByCurrentUser: issue.read_by_current_user,
    }
  end

  def ==(other)
    self.issue == other.issue
  end
end
