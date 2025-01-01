# typed: true
# frozen_string_literal: true

class DiscussionPollVote::Creator
  attr_reader :user, :option, :poll

  sig { returns DiscussionPollVote }
  attr_reader :vote

  delegate :errors, to: :vote

  sig { params(user: T.untyped, option: T.untyped).void }
  def initialize(user:, option:)
    @user   = user
    @option = option
    @poll   = option&.poll
    @vote   = DiscussionPollVote.new(poll: poll, option: option, user: user)
  end

  sig { returns T::Boolean }
  def create
    existing_vote = self.existing_vote
    if existing_vote.present? && existing_vote.discussion_poll_option_id == option.id
      @vote = existing_vote
      return true
    end

    result = T.let(false, T::Boolean)

    DiscussionPollVote.transaction do
      # We have to destroy the existing vote record instead of just updating it to avoid a race condition bug with
      # our `counter_cache` fields. See https://github.com/github/github/pull/212712#discussion_r826454531.
      existing_vote.destroy if existing_vote.present?

      result = vote.save

      # If saving tue new vote failed, we rollback to preserve the existing vote
      raise ActiveRecord::Rollback unless result
    end

    result
  end

  private

  sig { returns T.nilable(DiscussionPollVote) }
  def existing_vote
    return @existing_vote if defined?(@existing_vote)
    return @existing_vote = nil unless poll.present? && user.present?
    @existing_vote = poll.votes.find_by(user: user)
  end
end
