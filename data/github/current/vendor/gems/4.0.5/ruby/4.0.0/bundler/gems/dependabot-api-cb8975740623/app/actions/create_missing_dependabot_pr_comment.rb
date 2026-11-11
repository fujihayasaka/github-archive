# frozen_string_literal: true

require "github_helpers"

class CreateMissingDependabotPrComment
  include ActionView::Helpers::DateHelper

  attr_reader :pull_request

  # Constant copied here for convenience.
  DATA_RETENTION_PERIOD = ::ScheduledJobs::DeleteOldPullRequestsData::DATA_RETENTION_PERIOD

  def initialize(repo:, github_number:, comment_url:, pr_created_at:, pr_closed_at:)
    @pull_request = Stubs::PullRequest.new(repo: repo, github_number: github_number)
    @comment_url = comment_url
    @pr_created_at = pr_created_at
    @pr_closed_at = pr_closed_at
  end

  def run
    return unless pull_request.repo.account.active?

    create_missing_dependabot_pr_comment
  end

  private

  def create_missing_dependabot_pr_comment
    CreateComment.new(
      pull_request: pull_request,
      comment_body: comment_text,
    ).run
  end

  def comment_text
    return too_old_comment_text if @pr_closed_at && @pr_closed_at < DATA_RETENTION_PERIOD.ago
    return recently_created_comment_text if @pr_created_at && @pr_created_at > 1.hour.ago

    unknown_reason_comment_text
  end

  def too_old_comment_text
    <<~MSG.squish
      I can't perform [the requested action](#{@comment_url}) because this
      pull request was closed over #{time_ago_in_words(DATA_RETENTION_PERIOD.ago)} ago.
    MSG
  end

  def recently_created_comment_text
    <<~MSG.squish
      I can't perform [the requested action](#{@comment_url}) because this
      pull request was recently created and I'm still getting up to speed on it.
      Please try again later.
    MSG
  end

  def unknown_reason_comment_text
    <<~MSG.squish
      I can't perform [the requested action](#{@comment_url}) because I don't have any knowledge about this pull request.
    MSG
  end
end
