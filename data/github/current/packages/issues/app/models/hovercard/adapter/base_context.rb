# typed: true
# frozen_string_literal: true

class Hovercard::Adapter::BaseContext < Issue::Adapter::Base
  attr_reader :message
  attr_reader :octicon
  # the involvement context is a generic hovercard context defining how the user is involved with the hovercard
  # involvemnt can be an instance of either:
  # - IssueOrPullRequestHovercard::Contexts::ViewerInvolvement
  # - IssueOrPullRequestHovercard::Contexts::NotificationSubscriptionReason
  # - IssueOrPullRequestHovercard::Contexts::ReviewStatus
  def initialize(context, involvement:)
    super(context)

    @message = involvement.message
    @octicon = involvement.octicon
  end
end
