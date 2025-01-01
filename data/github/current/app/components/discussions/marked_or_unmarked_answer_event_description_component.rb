# typed: true
# frozen_string_literal: true

module Discussions
  class MarkedOrUnmarkedAnswerEventDescriptionComponent < ApplicationComponent
    include HydroHelper

    def initialize(event:, discussion:, timeline:)
      @event = event
      @discussion = discussion
      @timeline = timeline
    end

    attr_reader :event, :discussion, :timeline
    delegate :current_repository, to: :helpers
  end
end
