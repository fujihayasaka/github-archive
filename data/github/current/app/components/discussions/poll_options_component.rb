# typed: true
# frozen_string_literal: true

module Discussions
  class PollOptionsComponent < ApplicationComponent

    def initialize(poll:, poll_options: [], vote: nil, preview: false, locked: false)
      @poll = poll
      @poll_options = poll_options
      @vote = vote
      @preview = preview
      @locked = locked
    end

    def disable?
      preview || locked
    end

    def hidden?
      (!preview && !logged_in?) || vote.present? || locked
    end

    def checked?(option)
      return false if vote.nil?
      option.id == vote.discussion_poll_option_id
    end

    private

    attr_reader :poll, :poll_options, :preview, :vote, :locked
  end
end
