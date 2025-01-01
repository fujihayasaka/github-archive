# typed: true
# frozen_string_literal: true

class Discussions::Polls::VotesController < Discussions::BaseController
  before_action :login_required
  before_action :require_discussion
  before_action :require_poll
  before_action :require_poll_option

  def create
    voter = DiscussionPollVote::Creator.new(user: current_user, option: poll_option)

    if voter.create
      head :ok
    else
      render json: { error: voter.errors.full_messages.to_sentence }, status: 422
    end
  end

  private

  memoize def poll
    discussion = T.must_because(self.discussion) { "#require_discussion ensures non-nil" }
    discussion.poll
  end

  def require_poll
    render_404 unless poll
  end

  memoize def poll_option
    poll.options.find(params[:option_id])
  end

  def require_poll_option
    render_404 unless poll_option
  end
end
