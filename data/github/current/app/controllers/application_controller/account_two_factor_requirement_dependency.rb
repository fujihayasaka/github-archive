# typed: true
# frozen_string_literal: true

module ApplicationController::AccountTwoFactorRequirementDependency
  extend T::Helpers
  requires_ancestor { ApplicationController }

  BANNER_RECHECK_INTERVAL = 1.hour

  # Public: :before_action filter to evaluate if we should display the 2FA requirement banner
  def account_2fa_requirement_banner
    start = Time.now.utc
    return if !eligible_request? || is_banner_update_exempt?
    update_value = update_banner
    set_banner_update_exempt
  ensure
    GitHub.dogstats.timing("2fa_requirement_banner.overhead_ms", (Time.now.utc - T.must(start)).to_f * 1000, tags: ["banner_update:#{update_value}",
      "temp_exempt:#{!!session[:account_2fa_requirement_banner_exempt_until]}", "exempt:#{!!session[:account_2fa_requirement_banner_exempt]}"])
  end

  # Should we evaluate the banner for this request & environment?
  #
  # Returns boolean
  def eligible_request?
    !GitHub.single_or_multi_tenant_enterprise? &&
    request.format == :html &&
    request.get? &&
    !request.xhr? &&
    logged_in? &&
    !current_user.using_personal_access_token?
  end

  # Do we currently or permanently not need to update the banner state for the current_user
  #
  # Returns boolean
  def is_banner_update_exempt?
    return true if session[:account_2fa_requirement_banner_exempt]
    if session[:account_2fa_requirement_banner_exempt_until].present?
      return Time.now.utc < session[:account_2fa_requirement_banner_exempt_until]
    end

    false
  end

  # Re-evaluates if we should show the 2FA requirement banner for the current_user
  #
  # Returns update value - nil, "enabled", "required" for metrics
  def update_banner
    eligible_user = user_feature_enabled?(:bulwark_two_factor_required_feature) &&
      current_user.in_account_2fa_requirement_warning_state?

    # clear exempt values if it's time to check again
    clear_account_2fa_requirement_banner_values if check_banner_now?

    return false if !eligible_user || is_banner_update_exempt?

    # They've enabled 2FA and this is their first banner
    if current_user.two_factor_authentication_enabled?
      if current_user.last_account_2fa_requirement_banner_dismissed_at.nil?
        set_banner_value("enabled")
      end
    # They haven't enabled 2FA and haven't recently seen the banner
    elsif !current_user.two_factor_authentication_enabled? && !current_user.account_2fa_requirement_banner_recently_dismissed?
      set_banner_value("required")
    end
    session[:account_2fa_requirement_banner]
  end

  def set_banner_update_exempt
    if never_check_banner?
      set_banner_exempt
    elsif check_banner_later?
      set_banner_exempt(Time.now.utc + BANNER_RECHECK_INTERVAL)
    elsif current_user.account_2fa_requirement_banner_recently_dismissed?
      dismissed_until = current_user.last_account_2fa_requirement_banner_dismissed_at + 1.week
      set_banner_exempt(dismissed_until.utc)
    end
  end

  def never_check_banner?
    return true if current_user.account_two_factor_requirement_state.in?([:interrupt, :required])
    true if current_user.in_account_2fa_requirement_warning_state? && current_user.two_factor_authentication_enabled? && current_user.last_account_2fa_requirement_banner_dismissed_at
  end

  def check_banner_later?
    return true if !user_feature_enabled?(:bulwark_two_factor_required_feature)
    true if current_user.account_two_factor_requirement_state.in?([:optional, :exempt])
  end

  def check_banner_now?
    session[:account_2fa_requirement_banner_exempt_until] && session[:account_2fa_requirement_banner_exempt_until] < Time.now.utc
  end

  def set_banner_exempt(end_time = nil)
    clear_account_2fa_requirement_banner_values

    if end_time
      session[:account_2fa_requirement_banner_exempt_until] = end_time
    else
      session[:account_2fa_requirement_banner_exempt] = true
    end
  end

  def set_banner_value(two_factor_state)
    set_banner_exempt(Time.now.utc + BANNER_RECHECK_INTERVAL)
    session[:account_2fa_requirement_banner] = two_factor_state
  end

  def clear_account_2fa_requirement_banner_values
    session[:account_2fa_requirement_banner_exempt] = nil
    session[:account_2fa_requirement_banner_exempt_until] = nil
    session[:account_2fa_requirement_banner] = nil
  end

  # Public: :before_action filter to enforce the display of the two factor requirement interrupt interstitial
  #
  # Renders the two factor requirement interrupt interstitial if it's required for the current user.
  # Returns nil if the interrupt interstitial should NOT be displayed.
  def account_2fa_requirement_interrupt
    start = Time.now

    @required = show_account_2fa_requirement_interrupt?
    return unless @required

    GitHub.dogstats.increment("account_2fa_requirement_interrupt", tags: ["action:viewed"])
    log(
      msg: "Account 2fa requirement interrupt rendered",
      request_id: request_id,
      controller: params[:controller],
      action: params[:action],
      user_id: current_user.id,
    )

    interrupt_first_seen_at = T.let(current_user.two_factor_requirement_metadata.interrupt_first_seen_at, T.nilable(Time))
    if interrupt_first_seen_at.nil?
      # we need to explicitly connect to the write role since this before action
      # applies to GET requests which are read-role by default
      ActiveRecord::Base.connected_to(role: :writing) do
        interrupt_first_seen_at = Time.now.utc
        current_user.two_factor_requirement_metadata.update!(interrupt_first_seen_at: interrupt_first_seen_at)
      end
    end
    days_remaining = T.unsafe((T.must(interrupt_first_seen_at).to_date + User::AccountTwoFactorRequirementDependency::INTERRUPT_BYPASS_GRACE_PERIOD - Date.today)).to_i
    bypassable = current_user.can_bypass_account_2fa_requirement_interrupt?
    if bypassable && days_remaining <= 0
      days_remaining = 1
      GitHub.dogstats.increment("account_2fa_requirement_interrupt.bypass_discrepancy")
    end

    render(
      "settings/account_two_factor_requirement_interrupt",
      layout: "layouts/session_authentication",
      locals: {
        return_to: canonical_request.url,
        bypassable: bypassable,
        days_remaining: days_remaining,
      },
    )
  ensure
    GitHub.dogstats.timing("account_2fa_requirement_interrupt.overhead_ms", (Time.now - T.must(start)).to_f * 1000, tags: ["required:#{!!@required}"])
  end

  private

  def show_account_2fa_requirement_interrupt?
    return @show_account_2fa_requirement_interrupt if defined?(@show_account_2fa_requirement_interrupt)

    # Valid request types for the interrupt are HTML and wildcard
    format_check = request.format == :html || request.format.to_s == "*/*" ? true : false

    @show_account_2fa_requirement_interrupt = begin
      !GitHub.single_or_multi_tenant_enterprise? &&
      format_check &&
      !request.xhr? &&
      request.get? &&
      logged_in? &&
      !current_user.using_personal_access_token? &&
      current_user.account_2fa_requirement_interrupt_required?
    end
    GitHub.logger.info(
      "Bulwark interrupt request type",
      "request_format": request.format.to_s,
      "request_path": request.path,
      "show_interrupt": @show_account_2fa_requirement_interrupt,
    )
    @show_account_2fa_requirement_interrupt
  end
end
