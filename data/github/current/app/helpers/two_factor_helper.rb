# typed: true
# frozen_string_literal: true

module TwoFactorHelper
  extend T::Helpers

  sig { params(user: T.nilable(User)).returns(T.nilable(String)) }
  def backup_country_code(user)
    parts = backup_parts(user)
    @backup_country_code ||= parts ? parts[0] : ""
  end

  sig { params(user: T.nilable(User)).returns(T.nilable(String)) }
  def backup_national_number(user)
    parts = backup_parts(user)
    @backup_national_number ||= parts ? parts[1] : ""
  end

  # Gets the supported SMS countries.
  #
  # current - A country code string. If specified and country isn't supported,
  #           that country will be included in the returned Hash.
  #
  # Returns a Hash of country codes => country names.
  def sms_supported_countries(current = nil)
    if unsuported = GitHub::SMS::UNSUPPORTED_COUNTRY_CODES[current]
      combined = GitHub::SMS::SUPPORTED_COUNTRIES + unsuported
      combined.sort_by! { |_code, name| name }
    else
      GitHub::SMS::SUPPORTED_COUNTRIES
    end
  end

  def add_origin_bound_sms_footer(message, otp)
    # support for https://wicg.github.io/sms-one-time-codes/. The spec
    # calls for a newline followed by the "@origin #OTP".
    if use_origin_bound_codes?
      message = message.dup
      message << "\n\n"
      message << "@#{GitHub.host_domain} ##{otp}"
    end
    message
  end

  # Helper method to determine whether we want to add the origin to the SMS footer
  # Today, we never send the origin in the SMS footer.
  # We previously, conditionally added the origin to the SMS footer based on the country code of the outgoing SMS.
  # This was removed in
  # https://github.com/github/github/pull/331641/files#diff-171c4461f65bfd5eb422692789816c809e5f4cdc79bdbfb1f941ed152139dadc
  #
  # But as part of that removal, we no longer were following the spec (since we were missing the domain name).
  # After discussion amongst the team, we concluded that we won't ever add the footer to the SMS message.
  # It's a nice convenience, but we don't strive for convenience for SMS 2FA (to help push towards other, more secure 2FA methods).
  # ref: https://github.com/github/authentication/issues/4590
  def use_origin_bound_codes?
    false
  end

  # pass a hash of configured methods and their boolean statuses
  sig do
    params(
      configured_methods: T::Hash[Symbol, T::Boolean],
      user: T.nilable(User),
    ).returns(String)
  end
  def get_defaulted_two_factor_preference(configured_methods, user:)
    # if the user has no 2FA methods available, default to app.  This is definitely a bug.
    current_preference = user&.two_factor_credential&.login_preference

    # determine if current preference is usable by the current user
    can_use_preference = case current_preference
    when "webauthn_preferred"
      configured_methods[:security_keys] || configured_methods[:passkeys]
    when "github_mobile_preferred"
      configured_methods[:gh_mobile]
    when "app_preferred"
      configured_methods[:app]
    when "sms_preferred"
      configured_methods[:sms]
    else
      false
    end

    # set GitHub default preference if current preference is not set or not available
    if current_preference.nil? || !can_use_preference
      if configured_methods[:security_keys] || configured_methods[:passkeys]
        current_preference = "webauthn_preferred"
      elsif configured_methods[:gh_mobile]
        current_preference = "github_mobile_preferred"
      elsif configured_methods[:app]
        current_preference = "app_preferred"
      elsif configured_methods[:sms]
        current_preference = "sms_preferred"
      else
        # no known 2FA methods are available for this user, so default to app.  This is
        # almost certainly a bug.
        current_preference = "app_preferred"
      end
    end

    current_preference
  end

  # Determines whether we should lazyload the two factor holiday banner
  sig { params(user: T.nilable(User)).returns(T::Boolean) }
  def show_two_factor_holiday_banner?(user:)
    return false if GitHub.multi_tenant_enterprise? || GitHub.enterprise?
    return false unless holiday_warning_banner_date?
    return false if user&.is_emu_and_not_first_owner?
    return true if !T.unsafe(self).gist_request? && user&.feature_enabled?(:two_factor_holiday_warning_banner)

    gists_banner_enabled = user&.feature_enabled?(:gists_two_factor_holiday_warning_banner)
    return true if gists_banner_enabled
    false
  end

  sig do
    params(
      user: T.nilable(User),
      request: ActionDispatch::Request,
      session: ActionDispatch::Request::Session,
    ).returns(T::Boolean)
  end
  def account_2fa_requirement_banner_required?(user:, request:, session:)
    dotcom_request?(request) &&
    user.present? &&
    user.feature_enabled?(:bulwark_two_factor_required_feature) &&
    user.has_forthcoming_account_two_factor_requirement? &&
    !!session[:account_2fa_requirement_banner] &&
    !user.account_2fa_requirement_interrupt_required?
  end

  # Returns whether the current request is to the root dotcom subdomain (github.com), rather than a proper
  # subdomain (e.g. gist.github.com).  Should return true for development, test, review-lab environments.
  sig { params(request: ActionDispatch::Request).returns(T::Boolean) }
  def dotcom_request?(request)
    request.host == GitHub.host_domain
  end

  sig { params(methods: T::Array[Symbol]).returns(T.nilable(String)) }
  def self.display_two_factor_methods_text_list(methods)
    methods.any? ? methods.map { |m| display_two_factor_method_text(m) }.to_sentence : nil
  end

  sig { params(method: Symbol).returns(T.nilable(String)) }
  def self.display_two_factor_method_text(method)
    case method
    when :sms, :insecure
      "SMS/Text message"
    when :totp
      "Authenticator app"
    when :gh_mobile
      "GitHub Mobile"
    when :security_key
      "Security Keys"
    when :passkey
      "Passkeys"
    end
  end

  private

  # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
  sig { params(user: T.nilable(User)).returns(T.nilable(T::Array[String])) }
  def backup_parts(user)
    @backup_parts ||= begin
      if number = user&.two_factor_backup_sms_number
        number.split(" ", 2)
      end
    end
  end
  # rubocop:enable GitHub/BooleanMemoizationWithOrOperator

  # Determines whether the current time is within the holiday warning banner dates (Dec 10th - Jan 10th)
  def holiday_warning_banner_date?
    now = Time.now.utc
    (now.month == 12 && now.day >= 10) || (now.month == 1 && now.day <= 10)
  end
end
