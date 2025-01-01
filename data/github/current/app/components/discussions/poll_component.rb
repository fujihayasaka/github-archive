# typed: true
# frozen_string_literal: true

module Discussions
  class PollComponent < ApplicationComponent
    def initialize(discussion_number: nil, repository:, poll:, options:, preview: false, locked: false)
      @discussion_number = discussion_number
      @repository = repository
      @poll = poll
      @options = options
      @question = poll.question
      @preview = preview
      @locked = locked
    end

    def preview?
      @preview
    end

    def locked?
      @locked
    end

    def vote_button_disabled?
      preview? || voted? || locked?
    end

    memoize def vote
      return nil if @preview || !logged_in?
      poll_option_ids = options.map { |option| option.id }.compact
      DiscussionPollVote.find_by(user_id: current_user&.id, discussion_poll_id: poll.id, discussion_poll_option_id: poll_option_ids)
    end

    def voted?
      vote.present?
    end

    def total_votes
      poll.discussion_poll_votes_count.to_i
    end

    def discussion_poll_voting_path
      return if preview? || discussion_number.nil?
      discussion_poll_votes_path(repository.owner, repository, discussion_number)
    end

    def get_discussion_poll_path
      return if preview? || discussion_number.nil?

      discussion_poll_path(
        discussion_number: discussion_number,
        repository: repository,
        user_id: repository.owner
      )
    end

    private

    attr_reader :discussion_number, :repository, :poll, :options, :question

  end
end
