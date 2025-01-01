# typed: true
# frozen_string_literal: true

module ApplicationController::TwoFactorCheckupDependency
  extend ActiveSupport::Concern
  include ResilienceHelper

  extend T::Helpers
  requires_ancestor { ApplicationController }

  # Public: :before_action filter to enforce the display of the 2FA checkup interstitial
  # this action is skipped for the following controllers: Settings::SecuritiesController, TwoFactorController
  def require_two_factor_checkup
    return true unless show_two_factor_checkup?
    session[:return_to] = canonical_request.url

    render(
      "settings/two_factor_checkup/index",
      layout: "layouts/session_authentication",
      locals: {
        return_to: canonical_request.url,
        delayable: current_user.can_delay_two_factor_checkup?,
      },
    )
  end

  private

  def show_two_factor_checkup?
    return @show_two_factor_checkup if defined?(@show_two_factor_checkup)
    @show_two_factor_checkup = begin
      request.format == :html &&
      !GitHub.enterprise? &&
      logged_in? &&
      !current_user.using_personal_access_token? &&
      !request.xhr? &&
      request.get? &&
      !mobile? &&
      !gist_request? &&
      !two_factor_checkup_skip &&
      # 2FA checkup filter
      check_two_factor_checkup_due
    end

    @show_two_factor_checkup
  end

  def check_two_factor_checkup_due
    with_database_error_fallback(fallback: false) do
      if !current_user&.is_flagged_for_two_factor_checkup?
        session.delete(:snooze_2fa_checkup)
        session[:has_completed_2fa_checkup] = true
        return false
      end
      due = current_user&.is_due_for_two_factor_checkup?
      session[:snooze_2fa_checkup] = 1.day.from_now if !due
      due
    end
  end

  def two_factor_checkup_skip
    return true if session[:has_completed_2fa_checkup].present?
    # avoid KV read if we've already checked once today, this doesn't actually snooze the checkup itself
    session[:snooze_2fa_checkup].present? && session[:snooze_2fa_checkup] > Time.now
  end

  def clear_two_factor_checkup_value
    session.delete(:has_completed_2fa_checkup)
    session.delete(:snooze_2fa_checkup)
  end
end
