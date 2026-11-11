# typed: true
# frozen_string_literal: true

module Issues
  class IssueAssigneePickerComponent < ApplicationComponent
    include AvatarHelper
    include BotHelper

    def initialize(user:, assigned:, single_select:, profile_name:)
      @user, @assigned, @single_select, @profile_name = user, assigned, single_select, profile_name
      @login = user.display_login_legacy

      # For AgenticApp bots, use their display name
      if @user.is_a?(Bot)
        agent = AgenticApp.agent_for_bot_id(@user.id)
        if agent
          @agentic_app_display_name = agent.display_name
          @agentic_app_description = agent.display_owner
        end
      end

      # Fall back to their alias if there is no supplied profile_name
      # This is consistent with `safe_profile_name` in user.rb
      @profile_name = @login if @profile_name.blank?
    end
  end
end
