# typed: false
# frozen_string_literal: true
require "oidc/cap_validator"
# Defines context agnostic logic of the Azure AD conditional access policy.
module ConditionalAccess::Policy::ExternalConditionalAccessPolicy
  MESSAGE = <<~MSG.squish
    Forbidden: Access has been blocked by Conditional Access Policies defined in your identity provider. Please contact your identity provider administrator for more information.
  MSG

  # Computes applicability of this policy over N targets for conditional access.
  #
  # targets - an Enumerable of targets for conditional access,
  #           all resources provided MUST be of the same type.
  #
  # Returns Array[targets] that for which this policy is applicable.
  # The order of targets in the returned array is NOT guaranteed to match the input order.
  def multiple_external_conditional_access_policy_applicable(targets, target_provider)
    targets.filter do |resource|
      # This is only required to check for feature flag and can be removed when feature flag is being removed.
      target = target_provider.target(resource)
      next false unless target
      next false if target == :no_target_for_conditional_access
      business = business_from_target(target)
      next false unless business&.feature_enabled?(:idp_cap_for_web)

      external_conditional_access_policy_applicable(resource: resource, target_provider: target_provider) == :yes
    end
  end

  # Computes satisfiability of this policy over N targets for conditional access
  #
  # targets - an Enumerable of targets for conditional access
  #
  # Returns Array[targets] that for which this policy is satisfied
  def multiple_external_conditional_access_policy_satisfied(targets, target_provider)
    businesses = {}

    # The resources passed into this method are of the same type and should belong
    # to the same enterprise. It would be fine just to store a single value returned
    # from a call to external_conditional_access_policy_satisfied, but we are storing
    # a hash of businesses just in case in some future we might get resources
    # that belong to multiple businesses.  For example we might get here N number of
    # organizations that the user is a member of and it does not make sense to check
    # each of them against a policy that is defined at the business level.
    targets.filter do |resource|
      # This is only required to check for feature flag and can be removed when feature flag is being removed.
      target = target_provider.target(resource)
      next false unless target
      business = business_from_target(target)
      next false unless business&.feature_enabled?(:idp_cap_for_web)

      next businesses[business.id] if businesses.key?(business.id)

      businesses[business.id] = external_conditional_access_policy_satisfied(resource: resource, target_provider: target_provider) == :yes
    end
  end

  # Computes applicability of this policy for a target for conditional access. This method doesn't
  # check if the identity provider conditional access policy is satisfied for the given target though.
  # To check if the identity provider conditional access policy is satisfied for the given target too,
  # call the external_conditional_access_policy_satisfied method after this method.
  #
  # resource - Resource for conditional access
  # target - Target for conditional access
  #
  # Returns Symbol
  def external_conditional_access_policy_applicable(resource:, target_provider:)
    target = target_provider.target(resource)
    return :no if target == :no_target_for_conditional_access

    business = business_from_target(target)

    return :no unless business

    if GitHub.flipper[:log_applicable_external_conditional_access_policy].enabled?(business)
      log_applicable_external_conditional_access_policy(business, resource)
    end

    return :no unless business.enterprise_managed_user_enabled?
    return :no unless actor.is_a?(User) && actor.user?
    return :no if actor.instance_of?(User) && actor.site_admin?
    return :no if business.async_first_enterprise_owner?(user: actor).sync

    oidc_provider = business.async_oidc_provider.sync
    return :no unless oidc_provider.present?
    return :no unless oidc_provider.azure?

    return :no unless business.idp_based_ip_allowlist_configuration?
    return :no if actor.oauth_access && !actor.oauth_access.personal_access_token? && business.skip_idp_ip_allowlist_app_access_enabled?

    return :no if exempt_internal_github_resource?(business, resource)

    :yes
  end

  # Computes satisfiability of this policy for a target for conditional access. This method isn't
  # used independently, but rather with the external_conditional_access_policy_applicable method,
  # which first checks if the identity provider conditional access policy is applicable for a given target.
  #
  # resource - Resource for conditional access
  # target - Target for conditional access
  #
  # Returns Symbol
  def external_conditional_access_policy_satisfied(resource:, target_provider:)
    target = target_provider.target(resource)
    business = business_from_target(target)

    external_identity = actor.external_identities.first

    refresh_token = if business.feature_enabled?(:idp_cap_for_web)
      external_identity&.async_external_identity_refresh_token&.sync&.encrypted_refresh_token
    else
      external_identity&.external_identity_refresh_token&.encrypted_refresh_token
    end

    return :no unless refresh_token

    message = if business.feature_enabled?(:idp_cap_for_web)
      OIDC::CapValidator.satisfies_idp_web_cap?(business: business, refresh_token: refresh_token, client_ip: actor_ip, external_identity: external_identity)
    else
      OIDC::CapValidator.satisfies_idp_cap?(business: business, refresh_token: refresh_token, client_ip: actor_ip, external_identity: external_identity)
    end

    case message
    when :yes, :no
      message
    else
      @idp_message = message
      :no
    end
  end

  def log_applicable_external_conditional_access_policy(business, resource)
    oidc_provider = business.async_oidc_provider.sync

    GitHub.logger.info(
      "Applicability of external conditional access policy for resource",
      "code.function" => __method__,
      "gh.request.id" => GitHub.context[:request_id],
      "gh.business.name" => business.slug,
      "gh.external_cap.ip" => actor_ip,
      "gh.external_cap.enterprise_managed_user_enabled" => business.enterprise_managed_user_enabled?,
      "gh.external_cap.actor_is_user" => actor.present? && actor.is_a?(User) && actor.user?,
      "gh.external_cap.actor_is_site_admin" => actor.present? && actor.instance_of?(User) && actor.site_admin?,
      "gh.external_cap.first_enterprise_owner" => actor.present? && actor.is_a?(User) && actor.user? && business.async_first_enterprise_owner?(user: actor).sync,
      "gh.external_cap.oidc_provider_present" => oidc_provider.present?,
      "gh.external_cap.oidc_provider_azure" => oidc_provider.present? && oidc_provider&.azure?,
      "gh.external_cap.idp_based_ip_allowlist_configuration" => business.idp_based_ip_allowlist_configuration?,
      "gh.external_cap.actor_oauth_access_not_personal_access_token" => actor.present? && actor.is_a?(User) && actor.user? && actor.oauth_access.present? && !actor.oauth_access&.personal_access_token?,
      "gh.external_cap.skip_idp_ip_allowlist_app_access_enabled" => business.skip_idp_ip_allowlist_app_access_enabled?,
      "gh.external_cap.exempt_internal_github_resource" => exempt_internal_github_resource?(business, resource),
      "gh.external_cap.exempt_request_for_internal_ip" => business.feature_enabled?(:rescue_exempt_check_cap) ? exempt_request_for_internal_ip_with_rescue?(actor_ip) : exempt_request_for_internal_ip?(actor_ip),
      "gh.external_cap.exempt_request_for_internal_app" => actor.present? && exempt_request_for_internal_app?(actor: actor),
    )
  end

  # CAP's targets are either Businesses, Orgs or Users.
  # Note that this policy is only applicable for resources that live under an EMU business.
  def business_from_target(target)
    case target
    when Business
      target
    when Organization
      target.async_business.sync
    when User
      target.enterprise_managed_business
    else
      # We are ensured to have a User/Organization/Business target at this stage.
      # But just for safety, we raise.
      raise ArgumentError.new("unsupported target for conditional access: #{target.class.name}")
    end
  end

  # Exempt internal GitHub resources from external conditional access policy -
  # internal GitHub apps and internal GitHub IPs
  #
  # Returns a Boolean.
  def exempt_internal_github_resource?(business, resource)
    app_exempted = exempt_request_for_internal_app?(actor: actor)
    ip_exempted = if business.feature_enabled?(:rescue_exempt_check_cap)
      exempt_request_for_internal_ip_with_rescue?(actor_ip)
    else
      exempt_request_for_internal_ip?(actor_ip)
    end

    resource_id = if resource.respond_to?(:id) # User, Organization, Business, Integration
      resource.id
    elsif resource.respond_to?(:resource) && resource.resource.respond_to?(:id) # Platform::PublicResource
      resource.resource.id
    else
      nil
    end

    GitHub.logger.info(
      "Resource exemption status from external conditional access policy applicability",
      "code.function" => __method__,
      "gh.request.id" => GitHub.context[:request_id],
      "gh.app.class" => resource.class,
      "gh.app.id" => resource_id,
      "gh.external_identities.cap_exemption" => (app_exempted || ip_exempted) ? "exempted" : "not exempted",
      "gh.external_identities.internal_app_exempted" => app_exempted,
      "gh.external_identities.internal_ip_exempted" => ip_exempted,
      "gh.external_identities.client_ip" => actor_ip,
      "gh.business.name" => business.slug,
    )

    return true if app_exempted || ip_exempted

    false
  end

  # Apps on behalf of actors who don't take IP allow lists into consideration.
  #
  # These are internal apps that we have specifically designated with this
  # capability.
  def exempt_request_for_internal_app?(actor: nil)
    application = if actor.is_a?(Integration)
      actor
    elsif actor.is_a?(Bot) || actor.is_a?(SiteScopedIntegrationInstallation)
      actor&.integration
    elsif actor.is_a?(GitAuth::SSHKey)
      nil
    else
      actor.respond_to?(:oauth_access) && actor&.oauth_access&.application
    end
    return false unless application.present?

    Apps::Internal.capable?(:ip_allowlist_exempt, app: application)
  end

  # Check whether the current actor IP is coming from a GitHub-internal IP
  #
  # Returns a Boolean.
  def exempt_request_for_internal_ip?(client_ip)
    [
      "10.0.0.0/8",
    ].each do |cidr|
      range = IPAddr.new(cidr)
      return true if range.include?(client_ip)
    end
    false
  end

  # Check whether the current actor IP is coming from a GitHub-internal IP
  #
  # Returns a Boolean.
  def exempt_request_for_internal_ip_with_rescue?(client_ip)
    [
      "10.0.0.0/8",
    ].each do |cidr|
      begin
        range = IPAddr.new(cidr)
        return true if range.include?(client_ip)
      rescue IPAddr::InvalidAddressError
        return false
      end
    end

    false
  end
end
