# typed: true
# frozen_string_literal: true

module Discussions
  class TransferComponent < ApplicationComponent
    # timeline - a DiscussionTimeline
    def initialize(timeline:)
      @timeline = timeline
    end

    private

    attr_reader :timeline

    def render?
      logged_in? && GitHub.discussions_available_on_platform? && timeline&.can_transfer_discussion?
    end
  end
end
