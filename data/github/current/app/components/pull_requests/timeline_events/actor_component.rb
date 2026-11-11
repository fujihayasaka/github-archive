# typed: true
# frozen_string_literal: true

module PullRequests::TimelineEvents
  class ActorComponent < ApplicationComponent
    include AvatarHelper, BotHelper

    attr_reader :actor

    delegate :profile_link_user_name_display_configuration, to: :helpers

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
