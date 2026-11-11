# typed: true
# frozen_string_literal: true

module Discussions
  class PollResultsComponent < ApplicationComponent
    def initialize(poll:, poll_options:, vote: nil, locked: false)
      @poll = poll
      @poll_options = poll_options
      @vote = vote
      @locked = locked
    end

    def hidden?
      logged_in? && !vote.present? && !locked
    end

    def results
      results = poll_options.map do |poll_option|
        percent = if poll.discussion_poll_votes_count.to_i > 0
          poll_option.discussion_poll_votes_count.to_f / poll.discussion_poll_votes_count.to_f * 100
        else
          0
        end
        {
          option: poll_option.option,
          percent: percent.to_i,
          option_id: poll_option.id
        }
      end
    end

    def check_icon(option_id)
      show_icon = option_id == vote&.discussion_poll_option_id
      render(Primer::Beta::Octicon.new(ml: 1, icon: "check-circle", hidden: !show_icon, aria: { label: "You voted for this option" }))
    end

    private

    attr_reader :poll, :poll_options, :vote, :locked
  end
end
