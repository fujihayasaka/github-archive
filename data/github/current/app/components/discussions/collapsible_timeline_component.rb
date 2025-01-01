# typed: true
# frozen_string_literal: true

module Discussions
  class CollapsibleTimelineComponent < ApplicationComponent
    # timeline - a DiscussionTimeline
    # org_param - a string representing an Organization login
    sig do
      params(
        timeline: T.nilable(DiscussionTimeline),
        org_param: T.nilable(String)
      ).void
    end
    def initialize(timeline:, org_param:)
      @timeline = timeline
      @org_param = org_param
    end

    private

    attr_reader :timeline

    attr_reader :org_param

    def render?
      timeline.present? && GitHub.discussions_available_on_platform?
    end
  end
end
