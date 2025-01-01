# typed: true
# frozen_string_literal: true

module PullRequests::TimelineEvents
  class CommitActorComponent < ApplicationComponent
    include AvatarHelper, BotHelper

    def initialize(actor:)
      @actor = actor
    end

    memoize def visible_actor
      @actor.async_visible_actor(current_user).sync
    end

    def has_visible_actor?
      visible_actor.present?
    end

    memoize def actor_name
      @actor.name
    end

    def has_actor_name?
      actor_name.present?
    end
  end
end
