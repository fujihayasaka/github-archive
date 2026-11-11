# typed: true
# frozen_string_literal: true

class Site::Header::CopilotChatPanelComponent < ApplicationComponent
  include ResilienceHelper

  attr_reader :show_copilot_buttons, :show_copilot_title, :show_agents_button, :popover_available, :repository, :show_notification

  def initialize(
    show_copilot_buttons:,
    show_copilot_title:,
    show_agents_button:,
    popover_available:,
    repository:,
    show_notification:
  )
    @show_copilot_buttons = show_copilot_buttons
    @show_copilot_title = show_copilot_title
    @show_agents_button = show_agents_button
    @popover_available = popover_available
    @repository = repository
    @show_notification = show_notification
  end

  def render?
    show_copilot_buttons
  end
end
