# typed: true
# frozen_string_literal: true

class Site::Header::CopilotChatPanelComponent < ApplicationComponent
  include ResilienceHelper

  def render?
    GitHub.copilot_enabled? && logged_in? && not_in_immersive_view? && copilot_enabled?
  end

  def copilot_enabled?
    with_database_error_fallback(fallback: false) { helpers.show_copilot_chat_entrypoint? }
  end

  private

  def repo_for_react_partial
    return nil if current_repository.nil?

    attrs = {
      id: current_repository.id,
      name: current_repository.name,
      owner_login: current_repository.owner_display_login
    }

    Repos::ReactPayload.camelize_keys(attrs)
  end

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
