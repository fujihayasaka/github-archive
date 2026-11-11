# typed: true
# frozen_string_literal: true

class Site::Header::AgentsComponent < ApplicationComponent
  GLOBAL_AGENTS_BUTTON_ID = "global-copilot-agent-button"

  attr_reader :show_copilot_buttons, :show_copilot_title, :show_agents_button, :popover_available, :repository, :show_notification

  def initialize(
    show_agents_button:,
    popover_available:,
    repository:,
    show_notification:
  )
    @show_agents_button = show_agents_button
    @popover_available = popover_available
    @repository = repository
    @show_notification = show_notification
  end

  def render?
    show_agents_button
  end

  private

  def triangle_down_notification_class
    if show_notification
      return "AppHeader-button--hasIndicator AppHeader-button--attentionBackground"
    end

    ""
  end
end
