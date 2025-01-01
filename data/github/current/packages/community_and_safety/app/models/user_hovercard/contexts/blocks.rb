# typed: true
# frozen_string_literal: true

module UserHovercard::Contexts
  class Blocks < Hovercard::Contexts::Base
    def initialize(blocked_by_viewer:, blocking_org:)
      @blocked_by_viewer = blocked_by_viewer
      @blocking_org = blocking_org
    end

    def octicon
      "circle-slash"
    end

    def async_message
      if @blocking_org
        @blocking_org.async_profile.then do
          aux_verb = @blocked_by_viewer ? "have" : "has"
          "#{blockers.to_sentence.capitalize} #{aux_verb} blocked this user"
        end
      else
        Promise.resolve("You have blocked this user")
      end
    end

    def message
      async_message.sync
    end

    def platform_type_name
      "GenericHovercardContext"
    end

    private

    def blockers
      list = []
      list << "You" if @blocked_by_viewer
      list << "the #{@blocking_org.safe_profile_name} organization" if @blocking_org
      list
    end
  end
end
