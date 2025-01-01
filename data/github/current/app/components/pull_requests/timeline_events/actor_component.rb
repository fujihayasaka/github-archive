# typed: true
# frozen_string_literal: true

module PullRequests::TimelineEvents
  class ActorComponent < ApplicationComponent
    include AvatarHelper, BotHelper

    attr_reader :actor

    def initialize(actor:)
      @actor = actor
    end

    def actor?
      !!actor
    end

    memoize def ghost?
      actor&.ghost?
    end
  end
end
