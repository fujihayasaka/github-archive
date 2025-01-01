# typed: true
# frozen_string_literal: true

class Oauth::AuthorizeView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  include GitHub::Memoizer
  include ApplicationHelper # provides `coarse_time_ago_in_words`
  attr_reader :application, :approval, :authorization, :params, :redirect_uri,
    :rate_limited, :scopes, :session, :unauthorized_saml_organizations,
    :unauthorized_ip_allowlist_organization_ids, :form_submission_path,
    :include_device_warning, :device_authorization, :redirect_uri_specified
  attr_accessor :show_deleted

  delegate :came_from_marketplace?, :marketplace_listing_id, :logo_background_color_style_rule,
           to: :installation_view

  delegate :preferred_bgcolor, :owned_or_operated_by_github?, to: :application
  delegate :authorizable_organizations, to: :current_user

  # Array of relevant oauth params
  OAUTH_KEYS = [:client_id, :redirect_uri, :type, :state, :user_code]

  NON_PARENT_CHILD_RELATED_SCOPES = {
    packages: %w(write:packages read:packages delete:packages),
    org: %w(admin:org_hook),
    repo: %w(admin:repo_hook write:repo_hook read:repo_hook delete_repo public_repo),
  }

  # These scopes are used internally and should never have an impact on the scopes
  # displayed to a user
  INTERNAL_SCOPES = %w(user:assets user:assets:read)

  SCOPE_MODIFIERS = %w(admin read write delete manage_billing manage_runners scim)

  # this needs to be on one line or the linter needs to be updated.
  GENERIC_RENDERABLE_SCOPE_FAMILIES = %w(discussion gpg_key ssh_signing_key enterprise biztools workflow security_events codespace project audit_log copilot network_configurations)

  def self.scope_family(scope)
    return "repo" if scope == "public_repo"
    return "repo_status" if scope == "repo:status"

    parts = scope.split(":")
    SCOPE_MODIFIERS.include?(parts.first) ? parts.last : parts.first
  end

  # To ensure consistency and reduce maintenance
  # between the scopes and this view model, define
  # the access predicate methods using the scopes
  # from Api::AccessControl.
  #
  # Examples:
  #
  #   "repo" => repo_access?
  #
  #   "repo:invite" => repo_invite_access?
  #
  #   "write:discussion" => discussion_write_access?
  #
  ::Api::AccessControl.scopes.each do |scope, egress_scope|
    next if INTERNAL_SCOPES.include?(scope)

    parts = scope.split(":")
    parts = parts.reverse if SCOPE_MODIFIERS.include?(parts.first)
    name = parts.join(":").parameterize.underscore

    method_name = "#{name}_access?".to_sym

    define_method method_name do
      T.bind(self, Oauth::AuthorizeView)
      scopes.include?(scope)
    end

    if egress_scope.parent.nil?
      parent_parts = scope.split(":") - SCOPE_MODIFIERS
      parent_name = parent_parts.join(":").parameterize.underscore
      method_name = "no_#{parent_name}_access?".to_sym
      next if instance_methods.include?(method_name)
      define_method method_name do
        T.bind(self, Oauth::AuthorizeView)
        return false if scopes.include?(scope)

        child_scopes = ::Api::AccessControl.child_scopes(scope).flat_map { |s| s.send(:children) + [s] }.map(&:name)
        child_scopes += NON_PARENT_CHILD_RELATED_SCOPES.fetch(parent_name.to_sym, [])

        child_scopes.none? do |child_scope|
          scopes.include?(child_scope)
        end
      end
    end
  end

  # Public: Hash of oauth params to submit with authorization request.
  #
  # Returns a Hash.
  def oauth_params
    initial = {}
    initial[:redirect_uri_specified] = true if redirect_uri_specified

    OAUTH_KEYS.each_with_object(initial) do |key, hash|
      # We want to distinguish between a blank query parameter vs a `nil`
      # query parameter when generating the authorization form. If we don't, a
      # `nil` query parameter will get turned into a blank query parameter in
      # the form. For most implementations it shouldn't matter, but we have
      # seen OAuth applications that fall over if they don't provide a query
      # parameter and we send back a blank one in the response.
      next if params[key].nil?
      hash[key] = params[key]
    end
  end

  # Public: String of comma separated, normalized scopes requested as part of
  # authorization.
  #
  # Returns a String.
  def scope
    @scopes.join(",")
  end

  def scopes # rubocop:disable Lint/DuplicateMethods
    if existing_authorization?
      @scopes - @authorization.scopes
    else
      @scopes
    end
  end

  def all_scopes
    @scopes
  end

  def generically_renderable_family?(family)
    GENERIC_RENDERABLE_SCOPE_FAMILIES.include?(family)
  end

  # Public: Boolean if this application already has access.
  #
  # Returns truthy if the application already has access to this user.
  def existing_authorization?
    !!@authorization
  end

  # Public: Boolean if the application type is `Integration`.
  #
  # Returns true if there is an OauthAuthorization's application
  # is of type `Integration`.
  def integration_application_type?
    return false unless existing_authorization?
    @authorization.integration_application_type?
  end

  # Public: Boolean if this application already has access and is adding new
  # scopes.
  #
  # Returns truthy if the application already has access and is adding new
  # scopes.
  def adding_scopes?
    existing_authorization? && scopes.any?
  end

  # Public: Should OAuth access be blocked for this user because of mandatory
  # email verification?
  #
  # Returns a Boolean.
  def block_for_mandatory_email_verification?
    @block_for_mandatory_email_verification ||= begin
      GitHub.dogstats.increment "oauth.email_verification", tags: ["action:checked", "type:#{current_user.signup_timeframe}"]
      if current_user.must_verify_email?
        OauthAccess.instrument_email_verification_required(user: current_user, application_id: application.id)
        return true
      end
      false
    end
  end

  def requested_scope_families
    scopes.map do |s|
      next if INTERNAL_SCOPES.include?(s)
      self.class.scope_family(s)
    end.compact.uniq
  end

  def access_value(family)
    method = :"#{family}_access_value"
    public_send(method)
  end

  # User access
  #
  # https://developer.github.com/v3/oauth/#scopes
  alias full_user_access? user_access?

  # Public: Boolean limited user access is requested (either user:email or
  # user:follow scope).
  #
  # Returns truthly if limited user access is requested.
  def limited_user_access?
    !user_access? && (user_follow_access? || user_email_access? || user_read_access?)
  end

  # Public: Boolean if no user access is requested.
  #
  # Returns truthy if no access to user scope is requested.
  def no_user_access?
    !user_access? && !limited_user_access?
  end

  # Public: String CSS class value denoting the level of user access
  # that is requested.
  #
  # Returns a string suitable for a CSS class.
  def user_access_value
    classes = []
    classes << "full" if user_access?
    classes << "limited" << "limited-profile" if user_read_access?
    classes << "limited" << "limited-follow" if user_follow_access?
    classes << "limited" << "limited-email" if user_email_access?
    classes << "none" if classes.empty?
    classes.uniq!
    classes.join(" ")
  end

  # Repo access
  #
  # We define repo_access? above, this provides the full_repo_access? to
  # distinguish private "repo" scope from "public_repos" scope.
  #
  # https://developer.github.com/v3/oauth/#scopes
  alias full_repo_access? repo_access?

  # Public: String CSS class value denoting the level of repo access
  # that is requested.
  #
  # Returns a string suitable for a CSS class.
  def repo_access_value
    if repo_access?
      "full"
    elsif repo_invite_access? && public_repo_access?
      "public limited-repo-invite"
    elsif repo_invite_access?
      "default limited-repo-invite"
    elsif public_repo_access?
      "public"
    else
      "default"
    end
  end

  # Commit Status
  #

  # Public: String CSS class value denoting the level of repo:status access
  # that is requested.
  #
  # Returns a string suitable for a CSS class.
  def repo_status_access_value
    if repo_status_access?
      "full"
    else
      "none"
    end
  end

  # Deployment
  #

  # Public: String CSS class value denoting the level of repo_deployment access
  # that is requested.
  #
  # Returns a string suitable for a CSS class.
  def repo_deployment_access_value
    if repo_deployment_access?
      "full"
    else
      "none"
    end
  end

  # Orgs
  #
  #

  def org_access_value
    if org_admin_access?
      "full"
    elsif org_write_access?
      "write"
    elsif org_read_access?
      "read"
    else
      "none"
    end
  end

  # Notifications
  #
  # https://developer.github.com/v3/oauth/#scopes

  # Public: String CSS class value denoting the level of notifications access
  # that is requested.
  #
  # Returns a string suitable for a CSS class.
  def notifications_access_value
    if notifications_access?
      "read"
    elsif no_repo_access?
      "none"
    elsif public_repo_access?
      "via-public"
    elsif repo_access?
      "via-full"
    end
  end

  # Public keys
  #
  #

  def public_key_access_value
    if public_key_admin_access?
      "full"
    elsif public_key_write_access?
      "write"
    elsif public_key_read_access?
      "read"
    else
      "none"
    end
  end

  # Repo hooks
  #
  #

  def repo_hook_access_value
    if repo_hook_admin_access?
      "full"
    elsif repo_hook_write_access?
      "write"
    elsif repo_hook_read_access?
      "read"
    else
      "none"
    end
  end

  # Org hooks
  #
  #

  def org_hook_access_value
    if org_hook_admin_access?
      "full"
    else
      "none"
    end
  end

  # Gists
  #
  # https://developer.github.com/v3/oauth/#scopes

  # Public: String CSS class value denoting the level of gist access
  # that is requested.
  #
  # Returns a string suitable for a CSS class.
  def gist_access_value
    if gist_access?
      "full"
    else
      "none"
    end
  end

  # Pre-receive hooks

  def pre_receive_hook_access_value
    pre_receive_hook_admin_access? ? "full" : "none"
  end

  def packages_access_value
    case
    when packages_write_access? && packages_read_access?
      "full"
    when packages_write_access?
      "write"
    when packages_read_access?
      "read"
    else
      "none"
    end
  end

  # Enterprises

  def enterprise_access?
    enterprise_admin_access? || enterprise_read_access? || enterprise_manage_billing_access? || enterprise_manage_runners_access? || enterprise_scim_access?
  end

  def enterprise_access_value
    case
    when enterprise_admin_access?
      "admin"
    when enterprise_read_access?
      "read"
    when enterprise_manage_billing_access?
      "billing"
    when enterprise_manage_runners_access?
      "manage_runners"
    when enterprise_scim_access?
      "scim"
    else
      "none"
    end
  end

  def discussion_access_value
    case
    when discussion_write_access?
      "write"
    when discussion_read_access?
      "read"
    else
      "none"
    end
  end

  def gpg_key_access_value
    case
    when gpg_key_admin_access?
      "full"
    when gpg_key_write_access?
      "write"
    when gpg_key_read_access?
      "read"
    else
      "none"
    end
  end

  def ssh_signing_key_access_value
    case
    when ssh_signing_key_admin_access?
      "full"
    when ssh_signing_key_write_access?
      "write"
    when ssh_signing_key_read_access?
      "read"
    else
      "none"
    end
  end

  def workflow_access_value
    workflow_access? ? "full" : "none"
  end

  def biztools_access_value
    biztools_access? ? "full" : "none"
  end

  def security_events_access_value
    security_events_access? ? "full" : "none"
  end

  def codespace_access_value
    if codespace_access?
      "full"
    elsif codespace_secrets_access?
      "secrets"
    else
      "none"
    end
  end

  def copilot_access_value
    if copilot_access?
      "full"
    elsif copilot_manage_billing_access?
      "billing"
    else
      "none"
    end
  end

  def project_access_value
    if project_access?
      "full"
    elsif project_read_access?
      "read"
    else
      "none"
    end
  end

  def audit_log_access_value
    if audit_log_access?
      "full"
    elsif audit_log_read_access?
      "read"
    else
      "none"
    end
  end

  def network_configurations_access_value
    if network_configurations_write_access?
      "write"
    elsif network_configurations_read_access?
      "read"
    else
      "none"
    end
  end

  # Public: Boolean if no additional scopes have been requested.
  #
  # Returns truthy if this access request is only for identity and public information.
  def public_access_only?
    ::Api::AccessControl.scopes.values.all? do |egress_scope|
      next true if INTERNAL_SCOPES.include?(egress_scope.name)
      next true if egress_scope.parent.present?

      parts = egress_scope.name.split(":")
      name = SCOPE_MODIFIERS.include?(parts.first) ? parts.last : parts.first

      method_name = "no_#{name.parameterize.underscore}_access?".to_sym
      public_send(method_name)
    end
  end

  # Public: The subset of the user's organizations where the organization's
  # OAuth application policy either implicitly or explicitly permits the
  # application to access organization resources on behalf of organization
  # members.
  #
  # Returns an Array of Organizations.
  memoize def allowed_organizations
    authorized_organizations.oauth_app_policy_met_by(application)
  end

  # Public: The subset of the user's organizations where the organization's
  # OAuth application policy explicitly blocks the application access to
  # organization resources.
  #
  # Returns an Array of Organizations.
  memoize def blocked_organizations
    authorized_organizations.oauth_app_policy_blocks(application)
  end

  # Public: The subset of the user's organizations where the organization's
  # OAuth application policy explicitly denies the application access to
  # organization resources.
  #
  # Returns an Array of Organizations.
  memoize def denied_organizations
    authorized_organizations.oauth_app_policy_denies(application)
  end

  # Public: The subset of the user's organizations where the user can approve
  # the application to access organization resources on behalf of organization
  # members. These organizations meet the following criteria:
  #
  # - The organization's OAuth application policy restricts applications, and
  # - The organization has not approved this application, and
  # - The organization has not denied this application, and
  # - The user is an administrator for the organization.
  #
  # Returns an Array of Organizations.
  memoize def grantable_organizations
    owned_organizations - allowed_organizations - denied_organizations - blocked_organizations
  end

  # Public: The subset of the user's organizations where the user can request
  # organization approval for the application, or where there is already a
  # pending request for the organization to approve the application.
  #
  # Returns an Array of Organizations.
  memoize def requestable_organizations
    authorized_organizations - allowed_organizations - denied_organizations - grantable_organizations - blocked_organizations
  end

  # Public: Determine if all of the user's organizations permit the application
  # to access organization resources on behalf of organization members.
  #
  # Returns a Boolean.
  def all_organizations_allowed?
    authorized_organizations.length == allowed_organizations.length
  end

  # Public: Determine if the user belongs to at least one organization where
  # where the organization's OAuth application policy permits the application to
  # access organization resources on behalf of organization members.
  #
  # Returns a Boolean.
  def any_organizations_allowed?
    allowed_organizations.any?
  end

  # Public: Is the OAuth app being authorized for an account that has a paid
  # subscription?
  #
  # Returns a Boolean.
  def paid_marketplace_plan_purchased?
    installation_view.paid_marketplace_plan_purchased_by?(current_user)
  end

  # Public: Has the user clicked a link in the Integrations Directory.
  #
  # Returns a Boolean.
  def came_from_integrations_directory?
    last_listing_id    = session[:last_click_integration_listing_id]
    current_listing_id = application.integration_listing.try(:id)
    return false unless last_listing_id && current_listing_id
    last_listing_id.to_i == current_listing_id
  end

  # Public: Does the application have an approval requestor.
  #
  # Returns a Boolean.
  def application_approval_requester?
    !@approval.nil? && @approval.requestor.present?
  end

  # Public: Is this application blockable?
  #
  # Returns a Boolean.
  def application_blockable?
    application.present? && application.blockable_client_app?
  end

  # Public: Determine whether to show the Grant access button.
  #
  # Returns a Boolean.
  def show_grant_access_button?
    @approval.nil? || !@approval.approved?
  end

  # Public: Determine whether to show the Reauthorization button.
  #
  # Returns a Boolean.
  def rate_limited?
    existing_authorization? && !!@rate_limited
  end

  def application_creation_time_in_words
    if T.must(application.created_at) > 1.day.ago
      "less than a day"
    else
      coarse_time_ago_in_words(application.created_at)
    end
  end

  def application_user_count
    return @application_user_count if defined?(@application_user_count)

    user_ids = application.authorizations.limit(2000).pluck(:user_id)
    @application_user_count = User.not_spammy.where(id: user_ids).limit(1000).count
  end

  def application_user_range
    case application_user_count
    when 0...10
      "Fewer than 10"
    when 10...100
      "Fewer than 100"
    when 100...1000
      "Fewer than 1K"
    else
      "More than 1K"
    end
  end

  def application_redirect_origin
    Addressable::URI.parse(redirect_uri).origin
  end

  def application_github_owned?
    application.github_owned?
  end

  def application_owner
    @application.user
  end

  def owner_display_login
    application_owner.display_login
  end

  def authorized_organizations
    return @authorized_organizations if defined?(@authorized_organizations)
    @authorized_organizations = authorizable_organizations

    @unauthorized_saml_organizations = Array(@unauthorized_saml_organizations)

    # Also remove orgs that the user isn't authorised to access due to IP allow list enforcement
    @unauthorized_ip_allowlist_organization_ids = Array(@unauthorized_ip_allowlist_organization_ids)

    not_with_ids = @unauthorized_saml_organizations.map(&:id) + @unauthorized_ip_allowlist_organization_ids
    return @authorized_organizations if not_with_ids.empty?
    @authorized_organizations = @authorized_organizations.where.not(id: not_with_ids)
  end

  def device_authorization?
    oauth_params.key?(:user_code) && !oauth_params.key?(:redirect_uri)
  end

  def include_device_warning?
    !!@include_device_warning
  end

  def ip_address
    return @ip_address if defined?(@ip_address)
    @ip_address = @device_authorization.try(:ip)
  end

  def location
    return @location if defined?(@location)
    @location = @device_authorization.try(:location)
  end

  def location_available?
    ip_address.present? || location.present?
  end

  def device_code_created_at
    @device_authorization.created_at.to_formatted_s(:deprecation_mailer)
  end

  def allow_access_request_for?(org:)
    org.can_request_application_approval?(requestor: current_user)
  end

  private

  def owned_organizations
    return @owned_organizations if defined?(@owned_organizations)
    @owned_organizations = current_user.owned_organizations

    @unauthorized_saml_organizations = Array(@unauthorized_saml_organizations)

    # Also remove orgs that the user isn't authorised to access due to IP allow list enforcement
    @unauthorized_ip_allowlist_organization_ids = Array(@unauthorized_ip_allowlist_organization_ids)

    not_with_ids = @unauthorized_saml_organizations.map(&:id) + @unauthorized_ip_allowlist_organization_ids
    return @owned_organizations if not_with_ids.empty?
    @owned_organizations = @owned_organizations.where.not(id: not_with_ids)
  end

  def installation_view
    InstallationView.new(integratable: application, session: session, current_user: current_user)
  end
end
