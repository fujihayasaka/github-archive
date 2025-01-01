# typed: false
# frozen_string_literal: true

# External Identity Session controller concern
#
# See Also
#
#   ExternalIdentity model        - app/models/external_identity.rb
#   ExternalIdentitySession model - app/models/external_identity_session.rb
#   UserSession model             - app/models/user_session.rb
#
module ApplicationController::ExternalSessionsDependency
  extend ActiveSupport::Concern
  include EnterpriseManagedUsersHelper

  EMU_RECOVERY_SESSION_DEFAULT = "false"
  EMU_RECOVERY_SESSION_ALLOWED = "true"

  # Public: Returns the SamlEnforcementPolicy for the current
  # request. This is set during the SSO enforcement filter if the route and
  # organization are enforced.
  attr_accessor :current_saml_enforcement_policy
  attr_accessor :current_session_enforcement_policy

  included do
    helper_method :current_saml_enforcement_policy
    helper_method :current_session_enforcement_policy
    helper_method :current_external_identity_sessions
    helper_method :authorized_saml_organizations
    helper_method :unauthorized_saml_organizations
    helper_method :unauthorized_saml_organization_ids
    helper_method :current_external_identity_session
  end

  # Public: Checks if the required external identity session is present for
  # the current organization or business.
  #
  # If the organization or business does not require an external identity session,
  # short circuits out of the check.
  #
  # An organization requires an active external identity session when SAML SSO
  # is enabled. When enforced, every member must have an external identity and
  # session at all times. When enabled (without enforcement), only members
  # with a registered external identity must have a SAML session at all times.
  #
  # A business always requires an active external identity session when SAML SSO or OIDC
  # SSO is enabled. Business identity providers do not have an enforced flag.
  #
  # Example usage:
  #
  #     if !required_external_identity_session_present?
  #       render_external_identity_session_required
  #       return # abort access
  #     end
  #
  # Example scenarios:
  #
  #     required_external_identity_session_present?(target: nil)
  #     #=> true because no session is required (no organization to enforce)
  #
  #     required_external_identity_session_present?(target: non_saml_org)
  #     #=> true because no session is required (organization doesn't require SAML sessions)
  #     # authorization is enforced via organization membership checks (abilities)
  #
  #     logged_in? #=> false (anonymous)
  #     required_external_identity_session_present?(target: saml_org)
  #     #=> true because user must be logged in (no sessions, but also no org membership access)
  #     # authorization is enforced via organization membership checks (abilities)
  #
  #     saml_org.member?(current_user) #=> false (user isn't a member)
  #     required_external_identity_session_present?(target: saml_org)
  #     #=> true because user must be a member of the organization
  #     # authorization is enforced via organization membership checks (abilities)
  #
  #     saml_org.member?(current_user) #=> true
  #     # user does not have an active SAML session for the organization
  #     required_external_identity_session_present?(target: saml_org)
  #     #=> false, access must be aborted and the user prompted to SSO
  #
  #     saml_org.member?(current_user) #=> true
  #     # user has an active SAML session for the organization
  #     required_external_identity_session_present?(target: saml_org)
  #     #=> true, user meets criteria
  #
  #     saml_business.member?(current_user) #=> true
  #     required_external_identity_session_present?(target: saml_business)
  #     #=> true, SAML authentication is required when business SAML SSO is enabled
  #
  #     saml_business.member?(current_user) #=> false
  #     required_external_identity_session_present?(target: saml_business)
  #     #=> true, SAML authentication is required when business SAML SSO is enabled
  #
  # Returns false if the required active SAML session for the organization or business
  # is not present, or true if it is present or if no session is required.
  def required_external_identity_session_present?(target: safe_target_for_conditional_access)
    GitHub.tracer.in_span("required_external_identity_session_present?", kind: :internal) do |span|
      span.add_attributes(
        GitHub::TaggingHelper::CATALOG_SERVICE_TAG => "github/conditional_access",
        "code.function" => __method__.to_s,
        "code.namespace" => self.class.name
      )

      next true if target == :no_target_for_conditional_access

      next true if !target&.respond_to?(:external_identity_session_owner)

      if emu_oidc_target?(target: target&.external_identity_session_owner)
        self.current_session_enforcement_policy = external_session_enforcement_policy_for(target)
        next true unless current_session_enforcement_policy&.enforced?
      else
        self.current_saml_enforcement_policy = saml_enforcement_policy_for(target)
        next true unless current_saml_enforcement_policy&.enforced?
      end

      target = target&.external_identity_session_owner

      identity = current_external_identity(target: target)

      GitHub.context.push external_identity: identity
      Audit.context.push external_identity: identity

      # Skips checks for external identity in GHES with SCIM
      next true if target&.is_a?(Business) && target&.enterprise_server_scim_enabled?

      next true if current_user.is_first_emu_owner? && emu_admin_recovery_session_allowed?(target)

      identity.present?
    end
  end

  def set_emu_admin_recovery_session(target, expires)
    ExternalIdentities::KV.set(emu_admin_recovery_key_for_target(target),
      EMU_RECOVERY_SESSION_ALLOWED,
      expires: expires
    )
  end

  def emu_admin_recovery_session_allowed?(target)
    allowed = ExternalIdentities::KV.get(emu_admin_recovery_key_for_target(target)).value { EMU_RECOVERY_SESSION_DEFAULT }
    allowed == EMU_RECOVERY_SESSION_ALLOWED
  end

  def emu_admin_recovery_key_for_target(target)
    if emu_oidc_target?(target: target)
      "emu-admin-recovery-session-allowed-#{user_session.id}-#{target.external_provider.class.name}-#{target.external_provider.id}-#{current_user.id}"
    else
      "emu-admin-recovery-session-allowed-#{user_session.id}-#{target.saml_provider.class.name}-#{target.saml_provider.id}-#{current_user.id}"
    end
  end

  # Returns an Array of ExternalIdentitySession records for this
  # UserSession.
  def current_external_identity_sessions
    return [] unless logged_in? && user_session.present?

    @current_external_identity_sessions ||= user_session.
      external_identity_sessions.active.
      includes(external_identity: { provider: :target }).to_a
  end

  # Returns an Array of ExternalIdentity records for this
  # UserSession.
  def current_external_identities
    current_external_identity_sessions.map(&:external_identity).compact
  end

  def saml_for_user
    return @saml_for_user if defined?(@saml_for_user)
    @saml_for_user =
      if user_session
        Platform::Authorization::SAML.new(session: user_session) # rubocop:todo GitHub/DoNotInstantiatePlatformObjects
      else
        # for anonymous users, the SAML service object can handle a nil user
        Platform::Authorization::SAML.new(user: current_user) # rubocop:todo GitHub/DoNotInstantiatePlatformObjects
      end
  end

  # DEPRECATED: Finds all protected SAML SSO Organizations that the user currently has an
  # active external identity session for.
  # Consider using a Conditional Access Policy (CAP) method alternative if your intention is to filter resource(s).
  #
  # Read more: https://thehub.github.com/engineering/development-and-ops/dotcom/cap/update-callsite-to-cap-filtering
  def authorized_saml_organizations
    saml_for_user.authorized_organizations
  end

  # DEPRECATED: Consider using a Conditional Access Policy(CAP) method alternative if your intention is to filter resource(s).
  #
  # Read more: https://thehub.github.com/engineering/development-and-ops/dotcom/cap/update-callsite-to-cap-filtering
  def unauthorized_saml_organization_ids
    saml_for_user.protected_organization_ids
  end

  # Consider using a Conditional Access Policy(CAP) method alternative if your intention is to filter resource(s).
  #
  # Read more: https://thehub.github.com/engineering/development-and-ops/dotcom/cap/update-callsite-to-cap-filtering
  def unauthorized_saml_organizations
    saml_for_user.protected_organizations(include_businesses: true)
  end

  # Public: Returns the currently active ExternalIdentity
  # for the given authentication target, or nil otherwise.
  def current_external_identity(target: safe_target_for_conditional_access)
    return nil if target == :no_target_for_conditional_access
    target = target&.external_identity_session_owner
    return nil unless target.present?

    if emu_oidc_target?(target: target)
      current_external_identities.detect do |identity|
        identity.provider_type == target.external_provider.class.name &&
        identity.provider_id == target.external_provider.id
      end
    else
      current_external_identities.detect do |identity|
        identity.provider_type == target.saml_provider.class.name &&
        identity.provider_id == target.saml_provider.id
      end
    end
  end

  # Public: Returns the currently active ExternalIdentitySession
  # for the given authentication target, or nil otherwise.
  def current_external_identity_session(target: safe_target_for_conditional_access)
    return nil if target == :no_target_for_conditional_access

    # There is no external_identity_session_owner for a User
    return nil if target.is_a?(User) && (target.user? || target.bot? || target.mannequin?)
    target = target&.external_identity_session_owner
    return nil unless target.present?

    return nil unless external_provider_present?(target)

    current_external_identity_sessions.detect do |identity_session|
      next unless identity_session.external_identity&.provider
      identity_session.target == target
    end
  end

  # Public: Returns if there is a external provider for the given authentication target.
  #
  # Returns Boolean
  def external_provider_present?(target)
    return false unless target.present?
    case target
    when Business
      target.external_provider.present?
    when Organization
      target.saml_provider.present?
    else
      false
    end
  end

  # Public: Action filter to enforce enterprise access restriction for dotcom EMUs
  #
  # Most of this is covered by the EnterpriseAccessVerification web CAP, but there are some anonymous scenarios that require additional restrictions.
  # This method returns 403 if account creation is attempted when under an enterprise access restriction
  def restrict_enterprise_access
    if active_enterprise_access_restriction?
      if FeatureFlag.vexi.enabled?(:multiple_enterprise_access_verification, default: false)
        render plain: multiple_enterprise_access_verification_message(businesses_from_header), status: 403
      else
        render plain: enterprise_access_verification_message(business_from_header), status: 403
      end
    end
  end

  # Public: Action filter to enforce enterprise access restriction for dotcom EMUs
  #
  # Most of this is covered by the EnterpriseAccessVerification web CAP, but there are some anonymous scenarios that require additional restrictions.
  # This method redirects users to login if they attempt account creation when under an enterprise access restriction
  def enterprise_access_login_redirect
    if enterprise_access_improvements?
      if FeatureFlag.vexi.enabled?(:multiple_enterprise_access_verification, default: false)
        # always redirect to the first enterprise in the header
        safe_redirect_to business_idm_sso_enterprise_path(businesses_from_header[0])
      else
        safe_redirect_to business_idm_sso_enterprise_path(business_from_header)
      end
    end
  end

  # Public: Action filter to enforce required external identity sessions.
  #
  # Returns nothing.
  def require_active_external_identity_session
    if GitHub::AppEnvironment.development?
      if user_session && user_session.user
        user_session.user.reload unless user_session.user.respond_to?(:is_enterprise_managed?)
        if user_session.user.is_enterprise_managed?
          return false if FeatureFlag.vexi.enabled?(:emu_dev_bootstrap, user_session.user.enterprise_managed_business, default: false)
        end
      end
    end

    return unless GitHub.external_identity_session_enforcement_enabled?
    return true if signed_token_authed? # Signed auth token. No session.
    return true if external_identity_session_fresh?

    if request.xhr?
      head :unauthorized
    else
      render_external_identity_session_required
    end
  end

  # Public: Returns whether the external session for the request is "fresh" or
  # it we should prompt for SAML authentication. External sessions have a hard
  # cut-off expiration. And, sometimes this expiration occurs at an inconvenient
  # time. For example, it is generally more convenient to refresh your external
  # session during a page navigation than it is while posting a comment. So, as
  # expiration nears, we try to determine if it is a good time to refresh their
  # session.
  #
  # Returns true if we should prompt for SAML re-authentication or false
  # otherwise.
  def external_identity_session_fresh?
    # If their SAML session isn't present we need to prompt them
    return false unless required_external_identity_session_present?
    # Because required_external_identity_session_present? is true, we know the user
    # either has a valid external session or they are trying to access a resource that
    # doesn't require an external session. If current_external_identity_session.nil? is
    # true, we know it is the latter and can return early.
    return true if current_external_identity_session.nil?

    session_expiration = current_external_identity_session.expires_at
    session_duration = session_expiration - current_external_identity_session.updated_at

    # Most identity providers expire sessions after 24 hours. But, some
    # providers might expire session in as little as 1 hour. So, we vary the
    # refresh duration based on the length of the session.
    early_refresh_duration = if session_duration <= 2.hours
      5.minutes
    elsif session_duration <= 9.hours
      30.minutes
    else
      1.hour
    end

    eligible = session_expiration < early_refresh_duration.from_now
    if eligible && request.get? && !request.xhr?
      # We should have them refresh their external session.
      false
    else
      # We can let them continue using their currently active external session.
      true
    end
  end

  # Public: Guard to determine if an external identity session is required.
  #
  # By default, this is always on. Override with custom logic to conditionally
  # protect endpoints. For example, you may only want to enforce the filter for
  # private repository data and allow all access to public repository data.
  #
  # Returns true if an external identity session is required.
  def require_active_external_identity_session?
    true
  end

  # Public: Renders the SAML SSO prompt page, blocking access to protected
  # resources.
  #
  # Returns nothing.
  def render_external_identity_session_required(target: safe_target_for_conditional_access)
    if target == :no_target_for_conditional_access
      raise ArgumentError.new("unable to render external identity session required: unexpected :no_target_for_conditional_access")
    end
    target = target.external_identity_session_owner

    if target&.is_a?(Organization)
      allow_external_redirect_after_post(provider: target.saml_provider)
    else
      allow_external_redirect_after_post(provider: target.external_provider)
    end

    options = {}
    options[:return_to] = canonical_request.url if request.get? #defaults to org page downstream

    case target
    when ::Organization
      GlobalInstrumenter.instrument("sso_page.view", { user: current_user, org: target })

      view = create_view_model(
        Orgs::IdentityManagement::SingleSignOnView,
        form_data: captured_form_data_via_enforcement,
        organization: target,
        initiate_sso_url: org_idm_saml_initiate_url(target, options),
      )
      render "orgs/identity_management/sso", layout: "layouts/session_authentication", locals: { view: view }
    when ::Business
      GlobalInstrumenter.instrument("sso_page.view", { user: current_user, business: target })

      url = if target.oidc_enabled?
        idm_oidc_initiate_enterprise_url(target, options)
      else
        idm_saml_initiate_enterprise_url(target, options)
      end

      view = create_view_model(
        Businesses::IdentityManagement::SingleSignOnView,
        form_data: captured_form_data_via_enforcement,
        business: target,
        initiate_sso_url: url
      )
      render "businesses/identity_management/sso", layout: "layouts/session_authentication", locals: { view: view }
    end
  end

  # Private: Creates an active ExternalIdentitySession for the current_user
  # tied to the provisioned external identity.
  #
  # If a session already exists, it is updated with the given expiry.
  #
  # external_identity - The ExternalIdentity provisioned during SAML SSO.
  # expires_at - A DateTime specifying when the session should expire
  #
  # Returns an ExternalIdentitySession
  def update_or_create_external_identity_session(external_identity, expires_at:)
    if session = user_session.external_identity_sessions.by_identity(external_identity).active.first
      session.update(expires_at: expires_at)
    else
      session = user_session.external_identity_sessions.create \
        external_identity: external_identity,
        expires_at: expires_at
    end

    if current_user.feature_flag_enabled_or_raise?(:emu_user_session_expiration) && current_user.is_emu_and_not_first_owner? # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
      GitHub.dogstats.increment("account_switcher.set_emu_user_session_expiration.count")
      user_session.update(expires_at: session.expires_at)
    end

    session
  end

  # Private: Find the correct saml enforcement policy for the given authentication target
  #
  # Returns either a Business::SamlEnforcementPolicy or Organization::SamlEnforcementPolicy
  def saml_enforcement_policy_for(target)
    return unless target&.respond_to?(:external_identity_session_owner)

    provider_owner = target.external_identity_session_owner
    case provider_owner
    when ::Organization
      Organization::SamlEnforcementPolicy.new(organization: provider_owner, user: current_user)
    when ::Business
      organization = target.is_a?(::Organization) ? target : nil
      Business::SamlEnforcementPolicy.new(business: provider_owner, organization: organization, user: current_user)
    end
  end

  #  check feature flag state on a target
  def emu_oidc_target?(target:)
    target.present? && target.is_a?(Business) && target.oidc_enabled?
  end

  # Private: Find the correct saml enforcement policy for the given authentication target
  # Organizations belonging to a SAML enforced enterprise will return Business::SamlEnforcementPolicy
  #
  # Organizations and Busineses belonging to EMU will return Business::ExternalProviderEnforcementPolicy
  #
  # Returns Business::SamlEnforcementPolicy for GHES/GHEC standard businesses and organizations in those businesses
  # Returns Business::ExternalProviderEnforcementPolicy for GHEC EMUs
  # Returns Organization::SamlEnforcementPolicy for organizations enforcing level at org level.
  def external_session_enforcement_policy_for(target)
    return unless target&.respond_to?(:external_identity_session_owner)

    provider_owner = target.external_identity_session_owner
    case provider_owner
    when ::Organization
      Organization::SamlEnforcementPolicy.new(organization: provider_owner, user: current_user)
    when ::Business
      organization = target.is_a?(::Organization) ? target : nil
      Business::SamlEnforcementPolicy.new(business: provider_owner, organization: organization, user: current_user) if !provider_owner.enterprise_managed?
      Business::ExternalProviderEnforcementPolicy.new(business: provider_owner, user: current_user) if provider_owner.enterprise_managed?
    end
  end

  def captured_form_data_via_enforcement
    return nil if request.get?

    @captured_form_data ||= request.parameters.dup.tap do |p|
      p["_target"] = request.url

      p.delete "action"
      p.delete "controller"
    end
  end

  def saml_provider
    target = safe_target_for_conditional_access
    return nil if target == :no_target_for_conditional_access
    target = target.external_identity_session_owner
    target.try(:saml_provider)
  end

  def allow_external_redirect_after_post(provider: saml_provider)
    return unless provider.present?
    uri = Addressable::URI.parse(provider.sso_url)

    SecureHeaders.append_content_security_policy_directives(
      request,
      form_action: [uri&.origin],
    )
  end

  def filter_enterprise_managed_users
    return render_404 if !GitHub.enterprise? && logged_in? && current_user.is_emu_and_not_first_owner?
    true
  end
end
