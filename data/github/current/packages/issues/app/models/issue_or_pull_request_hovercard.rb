# typed: true
# frozen_string_literal: true

class IssueOrPullRequestHovercard
  # Used to identify via a URL parameter that we should show a hovercard for an IssueComment.
  ISSUE_COMMENT_TYPE = "issue_comment"

  # Used to identify via a URL parameter that we should show a hovercard for a
  # PullRequestReviewComment.
  REVIEW_COMMENT_TYPE = "review_comment"

  # Used to identify via a URL parameter that we should show a hovercard for the summary/body
  # of a PullRequestReview.
  REVIEW_TYPE = "review"

  attr_reader :issue_or_pull_request

  def initialize(issue_or_pull_request, include_notifications: true, viewer:)
    @issue_or_pull_request = issue_or_pull_request
    @viewer = viewer
    @include_notifications = include_notifications
  end

  def model
    issue_or_pull_request
  end

  def async_organization
    async_repository.then do |repo|
      repo.async_organization
    end
  end

  def async_repository
    issue_or_pull_request.async_repository
  end

  def contexts
    context_promises = [viewer_involvement_context, review_status_context]

    if @include_notifications
      context_promises << notification_subscription_reason
    end

    ::Promise.all(context_promises).then { |contexts| contexts.compact }
  end

  def platform_type_name
    "Hovercard"
  end

  private

  def viewer_involvement_context
    return Promise.resolve(nil) unless @viewer

    Contexts::ViewerInvolvement.async_resolve(
      issue_or_pull_request: issue_or_pull_request,
      viewer: @viewer,
    )
  end

  def review_status_context
    return Promise.resolve(nil) unless @viewer

    Contexts::ReviewStatus.async_resolve(issue_or_pull_request: issue_or_pull_request,
                                         viewer: @viewer)
  end

  def notification_subscription_reason
    return Promise.resolve(nil) unless @viewer

    Contexts::NotificationSubscriptionReason.async_resolve(
      issue_or_pull_request: issue_or_pull_request,
      viewer: @viewer,
    )
  end
end
