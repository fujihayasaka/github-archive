# typed: true
# frozen_string_literal: true

module MobileAppsHelper
  include ActionView::Helpers::ControllerHelper
  include ActionView::Helpers::TagHelper

  EXCLUDED_CONTROLLERS = %w(
    sessions
    signup
    oauth
  ).freeze

  # Public: App banner for the iOS app
  def ios_app_banner
    return unless render_ios_app_banner?

    tag(:meta, name: "apple-itunes-app", content: "app-id=#{GitHub.ios_app_id}, app-argument=#{request.url}")
  end

  # Internal: Determines whether we should render the mobile app meta header
  def render_ios_app_banner?
    !EXCLUDED_CONTROLLERS.include?(controller_name)
  end
end
