# typed: true
# frozen_string_literal: true

# A pull request displayed on the dashboard above the home feed.
class DashboardPullRequest
  attr_reader :pull_request

  def initialize(pull_request)
    @pull_request = pull_request
  end

  def to_json
    {
      title: pull_request.title,
      id: pull_request.id,
      updatedAt: pull_request.updated_at,
      permalink: pull_request.permalink,
      commentCount: pull_request.issue_comments_count
    }
    .to_json
  end

  def ==(other)
    self.pull_request == other.pull_request
  end
end
