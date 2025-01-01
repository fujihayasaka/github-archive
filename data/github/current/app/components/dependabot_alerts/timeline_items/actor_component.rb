# typed: true
# frozen_string_literal: true

module DependabotAlerts::TimelineItems
  class ActorComponent < ApplicationComponent
    include AvatarHelper, BotHelper

    attr_reader :actor

    def initialize(actor:)
      @actor = actor || User.ghost
    end

    def actor_is_dependabot?
      actor == :dependabot
    end

    def dependabot_image_path
      image_path("modules/site/security/dependabot-icon.png")
    end

    def dependabot_link_url
      "#{GitHub.help_url}/code-security/dependabot/dependabot-alerts"
    end
  end
end
