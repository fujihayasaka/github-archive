# typed: true
# frozen_string_literal: true

class Site::Header::AgentsComponent < ApplicationComponent
  GLOBAL_AGENTS_BUTTON_ID = "global-copilot-agent-button"
  private_constant :GLOBAL_AGENTS_BUTTON_ID

  attr_reader :repo_for_react_partial

  def initialize(repo_for_react_partial:)
    @repo_for_react_partial = repo_for_react_partial
  end

  def render?
    feature_enabled_globally_or_for_user?(feature_name: :copilot_global_agent_button) && copilot_coding_agent_enabled?
  end

  private

  def copilot_coding_agent_enabled?
    with_database_error_fallback(fallback: false) do
      Copilot::Public::User.new(current_user).swe_agent_enabled?
    end
  end

  def show_copilot_coding_agent_entry_point_popover?
    with_database_error_fallback(fallback: false) do
      CopilotSweAgent::Public.show_copilot_coding_agent_entry_point_popover?(current_user)
    end
  end

  def triangle_down_notification_class
    if !FeatureFlag.vexi.enabled?(:copilot_coding_agent_task_indicator, current_user, default: false)
      return ""
    elsif current_user.settings.get(:copilot_coding_agent_number_running_tasks) > 0
      return "AppHeader-button--hasIndicator AppHeader-button--attentionBackground"
    end

    ""
  end
end
