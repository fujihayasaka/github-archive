# typed: true
# frozen_string_literal: true

module Discussions
  class Comments::VotesController < Discussions::BaseController
    before_action :login_required
    before_action :require_discussion
    before_action :require_comment

    ERROR_MESSAGE = "Uh oh! You can't vote right now."
    RATING_LIMIT_ERROR_MESSAGE = "You've voted too many times recently. Please try again later."

    def update
      vote = comment.upvote(current_user)

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
      vote = DiscussionCommentVote.find_by(comment: comment, discussion: discussion, user: current_user)
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

    private

    memoize def comment
      discussion&.comments&.find(params[:comment_id])
    end

    def require_comment
      render_404 unless comment
    end
  end
end
