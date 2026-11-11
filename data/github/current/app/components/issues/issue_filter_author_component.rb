# typed: true
# frozen_string_literal: true

module Issues
  class IssueFilterAuthorComponent < ApplicationComponent
    include AvatarHelper
    include BotHelper

    def initialize(user:, url:, selected:)
      @user, @url, @selected = user, url, selected
    end

    def author_name
      if @user.is_a?(Bot)
        # for agentic app display display_name ex. Copilot, Claude or Codex
        agent = AgenticApp.agent_for_slug(@user.slug)
        return agent.display_name if agent

        # for regular bot display slug without [bot] suffix
        @user.display_login_legacy
      else
        @user.display_login
      end
    end
  end
end
