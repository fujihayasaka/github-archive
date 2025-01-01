# typed: true
# frozen_string_literal: true

class Discussions::VotesController < Discussions::BaseController
  before_action :login_required
  before_action :require_discussion

  ERROR_MESSAGE = "Uh oh! You can't vote right now."
  RATING_LIMIT_ERROR_MESSAGE = "You've voted too many times recently. Please try again later."

  def update
    discussion = T.must_because(self.discussion) { "#require_discussion ensures non-nil" }
    vote = discussion.upvote(current_user)
    if vote.errors.any?
      error = if vote.errors.full_messages.include?(GitHub::RateLimitedCreation::ERROR_MESSAGE)
        [ERROR_MESSAGE, RATING_LIMIT_ERROR_MESSAGE].join(" ")
      else
        ERROR_MESSAGE
      end

      render json: {
        error: error
      }, status: 422
    else
      head :ok
    end
  end

  def destroy
    vote = DiscussionVote.find_by(discussion: discussion, user: current_user)
    return head :ok unless vote

    vote.destroy

    if vote.errors.any?
      error = if vote.errors.full_messages.include?(GitHub::RateLimitedCreation::ERROR_MESSAGE)
        [ERROR_MESSAGE, RATING_LIMIT_ERROR_MESSAGE].join(" ")
      else
        ERROR_MESSAGE
      end

      render json: {
        error: error
      }, status: 422
    else
      head :ok
    end
  end
end
