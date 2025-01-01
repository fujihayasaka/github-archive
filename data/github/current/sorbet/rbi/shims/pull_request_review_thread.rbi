# typed: true
# frozen_string_literal: true

class PullRequestReviewThread
  # Defined via serialize :original_positioning
  sig { returns(T.nilable(PullRequests::CommentPosition::Positions)) }
  def original_positioning; end

  # Defined via serialize :latest_positioning
  sig { returns(T.nilable(PullRequests::CommentPosition::Positions)) }
  def latest_positioning; end
end
