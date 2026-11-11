# typed: true
# frozen_string_literal: true

module SmsRateLimitHelper
  extend T::Helpers
  requires_ancestor { TwoFactorController } # rubocop:disable GitHub/PreventViewHelpersInControllers

  # checks AuthenticationLimit rate limits for the send_two_factor_sms
  # send_two_factor_sms is used for 2FA _SETUP_ (initial configure via wizard, _or_ inline reconfigure)
  # we need to apply strict rate limitting to this endpoint to prevent abuse to SMS sending (which is expensive)
  # read more here: https://github.com/github/platform-health-incidents/issues/561
  # reminder that send_two_factor_sms is also rate limited by redis rate limits (rate_limit_requests) as a first tier limit
  # see TheHub docs on rate limiting with Redis limits + AuthenticationLimits (https://thehub.github.com/epd/engineering/dev-practicals/secure-coding/secure-coding-dotcom/authentication-and-rate-limits/)
  # returns true/false (true meaning rate limited) and the rate limit message if applied
  def is_send_two_factor_sms_authentication_rate_limited(number)
    country_code = number&.split(" ").first

    # we want to increment both login and IP limits _every_ time the action is called
    at_login_limit = AuthenticationLimit.at_any?(sms_2fa_setup_by_login: current_user.login, increment: true) # rubocop:disable GitHub/DoNotAllowLogin used in a query
    # only increment and check the IP limit if the calling user is marked as spammy
    at_ip_limit = false
    if current_user&.spammy?
      at_ip_limit = AuthenticationLimit.at_any?(sms_2fa_setup_by_spammy_ip: request.remote_ip, increment: true)
    end

    # check the login limit first
    # this matches the redis rate limit (rate_limit_requests) but is an extra check with higher persistence/durability
    if at_login_limit
      GitHub.dogstats.increment("two_factor_setup.render_sms_rate_limit", tags: ["by:authentication_limit_login", "applied:true", "country_code:#{country_code}"])
      return true, "You have exceeded our SMS rate limit. You will not be able to send another SMS for the next hour."
    end

    # the ip rate limit is restricted by spammy callers above
    # if we determine they are at this limit, check and increment _another_ login-based limit
    # that is configured mainly to allow a spammy caller to call this action once even if the IP limit is reached
    # we do this to be extra safe since IPs can be legitimately shared across account callers (e.g. VPNs or shared workspaces, etc.)
    if at_ip_limit
      if AuthenticationLimit.at_any?(sms_2fa_setup_spammy_ip_secondary_limit_by_login: current_user.login, increment: true) # rubocop:disable GitHub/DoNotAllowLogin used in a query
        GitHub.dogstats.increment("is_send_two_factor_sms_authentication_rate_limited.at_ip_limit", tags: ["at_secondary_limit:true"])
        GitHub.dogstats.increment("two_factor_setup.render_sms_rate_limit", tags: ["by:authentication_limit_ip", "applied:true", "country_code:#{country_code}"])
        GitHub.logger.info("Hit IP limit and secondary limit", {
          "code.namespace": self.class.name,
          "code.function": "is_send_two_factor_sms_authentication_rate_limited",
          "gh.enduser.id": current_user.id
        })
        return true, "You have exceeded our SMS rate limit."
      else
        GitHub.dogstats.increment("is_send_two_factor_sms_authentication_rate_limited.at_ip_limit", tags: ["at_secondary_limit:false"])
        GitHub.logger.info("Hit IP limit but did not apply it because the secondary limit was not hit", {
          "code.namespace": self.class.name,
          "code.function": "is_send_two_factor_sms_authentication_rate_limited",
          "gh.enduser.id": current_user.id
        })
      end
    end

    [false, nil]
  end
end
