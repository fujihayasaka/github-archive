# typed: true
# frozen_string_literal: true

module PullRequests::IntegrationDisplayNameHelper
  def user_display_login_or_bot_integration_name(user)
    if user.is_a?(Bot) && user.integration.present?
      reviewer_app = Apps::Internal.integration(:copilot_pull_request_reviewer)
      if reviewer_app.present? && reviewer_app.id == user.integration&.id
        return "Copilot"
      end

      return user.integration&.name
    end

    user.display_login
  end
end
