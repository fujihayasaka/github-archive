# typed: false
# frozen_string_literal: true

module EnterpriseManagedUsersHelper
  ENTERPRISE_ACCESS_HEADER = "HTTP_SEC_GITHUB_ALLOWED_ENTERPRISE"

  def emu_contribute_block_hint
    "You cannot contribute to repositories outside of your enterprise #{enterprise_name}."
  end

  # Does the request have a business slug header set for the enterprise access restriction policy
  def active_enterprise_access_restriction?
    !GitHub.enterprise? &&
    !GitHub.multi_tenant_enterprise? &&
    business_from_header.present?
  end

  # Enterprise access restriction policy check - applicable only to dotcom EMUs
  # the EnterpriseAccessVerification CAP handles all authenticated traffic,
  # but we need to also deny restricted logins
  # https://github.com/github/external-identities/issues/2706
  def is_enterprise_access_restricted?(login = nil)
    active_enterprise_access_restriction? &&
    business_by_login_shortcode(login) != business_from_header
  end

  # Redirects to the business SSO page if:
  # 1. security header is present
  # 2. is not an admin login
  #
  # Used for better login experience under enterprise access restriction
  def emu_header_login_redirect?
    enterprise_access_improvements? &&
    !params[:admin].present?
  end

  # UX improvements for anonymous flows like login and account creation under enterprise access restriction
  # Can only be done if the request has a unique URL parameter set, otherwise anonymous varnish caching will interfere
  def enterprise_access_improvements?
    return false unless active_enterprise_access_restriction?
    return true if logged_in?
    # for anonymous GET scenarios, make sure the request has a distinct param set so the URL is distinct from other cached requests
    params[:enterprise_access] == business_from_header.slug
  end

  # Get business from the enterprise access restriction header
  def business_from_header
    return @business_from_header if defined?(@business_from_header)
    header_value = request.env[ENTERPRISE_ACCESS_HEADER]
    return unless header_value.present?

    business_from_header = business_from_security_header(header_value)
    if business_from_header.present? && business_from_header.proxy_security_header_enabled?
      @business_from_header = business_from_header
    end

    @business_from_header
  end

  # Get business from the enterprise access restriction header
  def business_from_security_header(header_value)
    return unless header_value

    if integer?(header_value)
      Business.find_by(id: header_value.to_i)
    else
      Business.find_by(slug: header_value)
    end
  end

  def integer?(value)
    begin
      Integer value
    rescue
      return false
    end
    true
  end

  def business_by_login_shortcode(login = nil)
    return @business_by_login_shortcode if defined?(@business_by_login_shortcode)
    login ||= params[:login]
    return unless login.present?
    return unless login.include?("_")

    # we don't allow email logins for EMUs because we can't identity the enterprise
    return if User.valid_email?(login)

    shortcode = login.split("_")[1]
    # Check if this is the first admin account
    shortcode = login.split("_")[0] if shortcode == Business::ManagedUserDependency::ADMIN_SUFFIX
    return unless shortcode.present? && shortcode.match(Business::SHORTCODE_REGEX)

    @business_by_login_shortcode = Business.find_by(shortcode: shortcode)
    @business_by_login_shortcode
  end

  def enterprise_access_verification_message(business)
    "Your network administrator has blocked access to GitHub except for the '#{business.name}' Enterprise. Please sign in with your '_#{business.shortcode}' account to access GitHub."
  end

  def emu_contribute_block_warning
    return emu_contribute_block_hint unless logged_in?
    return emu_contribute_block_hint unless account_switcher_helper&.enabled?

    non_emu_accounts = account_switcher_helper.stashed_accounts.valid.select do |account|
      !account.user.is_enterprise_managed?
    end

    return emu_contribute_block_hint unless non_emu_accounts.any?

    render partial: "sessions/account_switcher_emu_block_hint", locals: {
      stashed_accounts: non_emu_accounts,
      warning_message: emu_contribute_block_hint,
      return_to: canonical_request.path,
    }
  end

  # This leverages the ConditionalAccess::View::Filter
  def emu_contribution_blocked?(resource)
    !cap_view_filter.authorized?(resource: resource, policy: :emu_ownership)
  end

  # Checks if the login follows the enterprise managed user pattern
  def is_emu_login?(login)
    return false if GitHub.enterprise?
    return false unless login.present?
    return false if login.include?("_#{User::EnterpriseManagedDependency::ADMIN_SUFFIX}")
    return false if User::EnterpriseManagedDependency::INVALID_UNDERSCORE_LOGIN.include?(login)

    login.include?("_")
  end

  # EMU "Outside collaborators" are presented as "Repository collaborators" to customers
  def outside_collaborators_verbiage(actor)
    business = if actor.is_a?(Business)
      actor
    elsif actor.is_a?(Organization)
      actor&.business
    elsif actor.is_a?(User)
      actor&.business
    else
      nil
    end

    return "repository collaborators" if business&.emu_repository_collaborators_enabled?

    GitHub.outside_collaborators_flavor
  end

  def can_user_disable_emu_sso?(user:, business:)
    !!business&.is_first_emu_owner?(user: user)
  end

  private

  def enterprise_name
    current_user&.enterprise_managed_business&.name
  end
end
