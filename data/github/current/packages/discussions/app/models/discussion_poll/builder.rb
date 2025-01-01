# typed: true
# frozen_string_literal: true

class DiscussionPoll
  class Builder
    sig { params(discussion: T.untyped, user: T.untyped).void }
    def initialize(discussion, user)
      @discussion = discussion
      @user = user
    end

    sig { params(question: T.untyped, options: T.untyped).returns(T.untyped) }
    def build(question:, options:)
      poll = DiscussionPoll.new(
        discussion: @discussion,
        question: question,
        discussion_poll_votes_count: 0
      )
      options.each do |option|
        poll.options.build(
          poll: poll,
          option: option,
          discussion_poll_votes_count: 0
        )
      end
      poll
    end
  end
end
