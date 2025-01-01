# typed: true
# frozen_string_literal: true

class Site::Header::CopilotChatPanelComponent < ApplicationComponent
  include CopilotChatHelper
  include ResilienceHelper

  def render?
    if copilot_floating_button_flag_enabled?
      return GitHub.copilot_enabled? && logged_in? && not_in_immersive_view?
    end

    GitHub.copilot_enabled? && logged_in? && not_in_immersive_view? && copilot_enabled?
  end

  def copilot_enabled?
    with_database_error_fallback(fallback: false) { copilot_chat_enabled_for_current_user? }
  end

  private

  def not_in_immersive_view?
    request_path != copilot_immersive_path
  end

  memoize def request_path
    # The following is to grab the first non-empty string after splitting on "/" so that
    # both production and test environments are happy.
    # In production: request_path = "/copilot"
    # In tests: request_path = "//copilot"
    "/#{request&.path.to_s.split("/").find(&:present?)}"
  end
end
