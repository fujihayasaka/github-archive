# typed: true
# frozen_string_literal: true

class Site::Header::CopilotChatPanelComponent < ApplicationComponent
  attr_reader :current_user, :current_repository, :current_organization

  delegate :agents_panel_payload, :copilot_panel_payload, to: :copilot_payload

  def initialize(
    current_user:,
    current_organization:,
    current_repository:
  )
    @current_user = current_user
    @current_organization = current_organization
    @current_repository = current_repository
  end

  memoize def copilot_payload
    GlobalNavigation::CopilotPayload.new(
      current_user: current_user,
      current_copilot_user: current_copilot_user_v2,
      current_repository: current_repository,
      source: "react_partial"
    )
  end

  def render?
    copilot_payload.payload[:show]
  end

  def copilot_chat_url
    copilot_payload.payload[:copilotChatUrl]
  end

  def copilot_button_url
    if should_redirect_to_agents?
      "/copilot/agents"
    else
      "/copilot"
    end
  end

  def copilot_button_aria_label
    if should_redirect_to_agents?
      "Navigate to Copilot"
    else
      "Chat with Copilot"
    end
  end

  private

  def user_has_agent_access?
    return false unless current_user

    with_database_error_fallback(fallback: false) do
      copilot_user = Copilot::Public::User.new(current_user)
      copilot_user.swe_agent_enabled?
    end
  end

  def should_redirect_to_agents?
    feature_enabled_globally_or_for_user?(feature_name: :copilot_default_to_task_input) && feature_enabled_globally_or_for_user?(feature_name: :copilot_redirect_header_button_to_agents) && user_has_agent_access?
  end
end
