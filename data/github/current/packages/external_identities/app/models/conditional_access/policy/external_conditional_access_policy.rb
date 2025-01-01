# typed: false
# frozen_string_literal: true

require "oidc/cap_validator"
# Defines context agnostic logic of the Azure AD conditional access policy.
module ConditionalAccess::Policy::ExternalConditionalAccessPolicy
  include ConditionalAccess::Policy::EmuPoliciesHelper

  MESSAGE = <<~MSG.squish
    Forbidden: Access has been blocked by Conditional Access Policies defined in your identity provider. Please contact your identity provider administrator for more information.
  MSG

  def get_actor_ip(business)
    if actor_ip.present?
      return actor_ip
    end
    if GitHub.context[:actor_ip].present?
      return GitHub.context[:actor_ip]
    end
    nil
  end

  # Computes applicability of this policy over business of the actor for conditional access.
  #
  # targets - an Enumerable of targets for conditional access,
  #           all resources provided MUST be of the same type.
  #
  # Returns Array[targets] that for which this policy is applicable.
  # The order of targets in the returned array is NOT guaranteed to match the input order.
  def multiple_external_conditional_access_policy_applicable(targets, target_provider)
    return [] if anonymous?
    # targets passed into this method belongs to the same enterprise as the actor
    # therefore we can safely use the enterprise of the actor to determine the enterprise to apply the policy
    return [] unless actor.is_a?(User) && actor.user?

    business = business_for(actor)
    return [] unless business&.idp_cap_for_web_enabled?

    GitHub.logger.info(
      "Applicability of external conditional access policy for resources via filter",
      "code.function" => __method__,
      "gh.request.id" => GitHub.context[:request_id],
      "gh.business.name" => business&.slug,
      "gh.actor.id" => actor&.id,
      "gh.actor.login" => actor&.display_login,
    )

    return [] unless external_conditional_access_policy_applicable(resource: business, target_provider: target_provider) == :yes

    targets
  rescue Platform::Errors::Execution => e
    GitHub.logger.info(
      "Applicability of external conditional access policy for resources via filter raised Platform::Errors::Execution",
      "code.function" => __method__,
      "error.message" => e.message,
      "gh.request.id" => GitHub.context[:request_id],
    )

    []
  end

  # Computes satisfiability of this policy over business of the actor for conditional access.
  #
  # targets - an Enumerable of targets for conditional access
  #
  # Returns Array[targets] that for which this policy is satisfied
  def multiple_external_conditional_access_policy_satisfied(targets, target_provider)
    # handle public, internal and private visibility if applicable
    # this plattform change should not result in a change of behaviour - behaviour change will come in a follow-up
    # multiple_external_conditional_access_policy_satisfied is only used by the CAP Filter
    result = Hash.new { |h, k| h[k] = {} }
    business = business_for(actor)

    # multiple_external_conditional_access_policy_applicable would already return not applicable
    # therefore most of those checks wouldn't apply
    # keeping them because consider_visibility doesn't want to introduce any behaviour changes yet
    compute_satisfied = if !(actor.is_a?(User) && actor.user?) || !business&.idp_cap_for_web_enabled?
      false
    else
      true
    end
    satisfied = compute_satisfied ? external_conditional_access_policy_satisfied(resource: business, target_provider: target_provider) == :yes : true

    GitHub.logger.info(
      "Satisfiability of external conditional access policy for resources via filter",
      "code.function" => __method__,
      "gh.request.id" => GitHub.context[:request_id],
      "gh.business.name" => business&.slug,
      "gh.actor.id" => actor&.id,
      "gh.actor.login" => actor&.display_login,
      "candidate" => true,
    )

    targets.each do |target|
      result[target] = {
        # External Conditional Access policy satisfied for private
        "private": satisfied ? :satisfied : :unsatisfied,
      }
    end
    result
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

    unless get_actor_ip(business)
      GitHub.logger.info(
        "External conditional access policy inapplicable due to empty IP",
        "code.function" => __method__,
        "gh.request.id" => GitHub.context[:request_id],
        "gh.business.name" => business.slug,
        "gh.external_cap.ip" => get_actor_ip(business),
      )
      GitHub.dogstats.increment("external_conditional_access_policy.inapplicable_empty_ip")
      return :no
    end

    if FeatureFlag.vexi.enabled?(:log_applicable_external_conditional_access_policy, business, default: false)
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

    message = if business.idp_cap_for_web_enabled?
      OIDC::CapValidator.satisfies_idp_web_cap?(business: business, client_ip: get_actor_ip(business), external_identity: external_identity)
    else
      OIDC::CapValidator.satisfies_idp_cap?(business: business, client_ip: get_actor_ip(business), external_identity: external_identity)
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
      "gh.external_cap.ip" => get_actor_ip(business),
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
      "gh.external_cap.exempt_request_for_internal_ip" => exempt_request_for_internal_ip_with_rescue?(get_actor_ip(business)),
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
    ip_exempted = exempt_request_for_internal_ip_with_rescue?(get_actor_ip(business))

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
      "gh.external_identities.client_ip" => get_actor_ip(business),
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

    Apps::Privileged.capable?(:ip_allowlist_exempt, app: application)
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
