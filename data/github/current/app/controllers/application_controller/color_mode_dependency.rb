# typed: true
# frozen_string_literal: true

module ApplicationController::ColorModeDependency
  extend ActiveSupport::Concern
  extend T::Helpers
  requires_ancestor { ApplicationController }

  def set_color_mode_cookie
    return unless logged_in?
    return if GitHub.enterprise?

    cookies[:color_mode] = {
      value: JSON.generate({
        color_mode: current_user.color_mode_with_default,
        light_theme: {
          name: current_user.light_theme.name,
          color_mode: current_user.light_theme.color_mode.name
        },
        dark_theme: {
          name: current_user.dark_theme.name,
          color_mode: current_user.dark_theme.color_mode.name
        },
      }),
      domain: cookie_domain
    }
  end
end
