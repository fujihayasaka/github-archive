# typed: true
# frozen_string_literal: true

module ApplicationController::TwoFactorHolidayWarningDependency
  extend ActiveSupport::Concern
  include GitHub::Memoizer
  include TwoFactorHelper

  extend T::Helpers
  requires_ancestor { ApplicationController }

  # Public: :before_action filter to enforce the display of the holiday 2FA warning
  def require_two_factor_holiday_warning
    session[:two_factor_holiday_warning_banner] = nil
    return unless show_two_factor_holiday_warning?

    GitHub.dogstats.increment("two_factor.holiday_warning_banner.shown")
    session[:two_factor_holiday_warning_banner] = true
  end

  private

  memoize def show_two_factor_holiday_warning?
    # general request requirements
    return false if GitHub.enterprise?
    return false unless internal_or_direct_referrer?
    return false unless request.get? && request.format == :html
    return false if mobile? || gist_request?
    return false unless logged_in?
    return false if current_user.using_personal_access_token?

    # specific requirements for 2FA holiday warning banner
    if !holiday_warning_banner_date?
      clear_two_factor_holiday_warning_session
      return false
    end

    return false unless FeatureFlag.vexi.enabled?(:two_factor_holiday_warning_banner, default: false)
    return false if session[:has_dismissed_two_factor_holiday_warning].present?
    check_two_factor_holiday_warning
  end

  # Checks if the user should see the two factor holiday warning banner
  def check_two_factor_holiday_warning
    with_database_error_fallback(fallback: false) do
      # If the user has already dismissed the banner,
      # then we don't need to check if they should see it.
      if current_user.two_factor_holiday_warning_dismissed?
        session[:has_dismissed_two_factor_holiday_warning] = true
        return false
      end

      current_user.should_see_two_factor_holiday_warning?
    end
  end

  def clear_two_factor_holiday_warning_session
    if session[:has_dismissed_two_factor_holiday_warning]
      session.delete(:has_dismissed_two_factor_holiday_warning)
    end
  end
end
