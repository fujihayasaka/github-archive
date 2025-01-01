# typed: true
# frozen_string_literal: true

class Api::Organizations < Api::App
  include Api::App::SecretScanningHelpers
  include Api::App::SecurityAnalysisSettingsHelpers
  include ReceiveSchemaWithOpenApi
  include SecurityAnalysisSettingsHelper

  # list the logged in user's organizations (public and private)
  get "/user/orgs", operation_id: "orgs/list-for-authenticated-user" do
    @accepted_scopes = %w(admin:org read:org repo user write:org)

    set_forbidden_message "You need at least read:org scope or user scope to list your organizations."
    control_access :list_current_user_accessible_orgs,
      challenge: true,
      resource: current_user,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    orgs = paginate_rel(accessible_orgs.includes(:profile))

    deliver :organization_hash, orgs
  end

  # list the logged in user's organization memberships (public and private)
  get "/user/memberships/orgs", operation_id: "orgs/list-memberships-for-authenticated-user" do
    set_forbidden_message "You do not have access to organization memberships."
    control_access :get_current_user_org_membership,
      resource: current_user,
      member: current_user,
      challenge: true,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    state = params[:state] && params[:state].strip

    if state.present? && %w(active pending).exclude?(state)
      deliver_error! 422,
        message: "If you pass a state to this endpoint, it must be either 'pending' or 'active'.",
        documentation_url: "/v3/orgs/#list-your-organization-memberships"
    end

    include_active  = state.blank? || state == "active"
    include_pending = state.blank? || state == "pending"

    org_ids = []
    org_ids |= current_user.organization_ids        if include_active
    org_ids |= current_user.invited_organizations.map(&:id) if include_pending

    org_ids = ProgrammaticActor::OrganizationFilter.perform(
      actor: current_user, organization_ids: org_ids, resource: "members"
    )

    scope = Organization.where(id: org_ids).includes(:profile, :business)

    if requestor_governed_by_oauth_application_policy?
      scope = T.unsafe(scope).oauth_app_policy_met_by(current_app_via_oauth)
    end

    orgs = paginate_rel(scope)
    GitHub::PrefillAssociations.prefill_batch_method(orgs, :repository_counts)

    deliver :org_membership_hash, orgs, user: current_user
  end

  # get the logged in user's membership with an org
  get "/user/memberships/organizations/:organization_id", operation_id: "orgs/get-membership-for-authenticated-user" do
    org = find_org!

    set_forbidden_message "You do not have access to this organization membership."
    control_access :get_current_user_org_membership,
      member: current_user,
      resource: org,
      challenge: true,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    if org.membership_state_of(current_user) == :inactive
      deliver_error 404
    else
      deliver :org_membership_hash, org, user: current_user
    end
  end

  # update the logged in user's membership with an org
  patch "/user/memberships/organizations/:organization_id", operation_id: "orgs/update-membership-for-authenticated-user" do
    org = find_org!

    set_forbidden_message "You do not have access to this organization membership."
    control_access :update_current_user_org_membership,
      resource: current_user,
      organization: org,
      challenge: true,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    data = receive(Hash)

    if org.membership_state_of(current_user) == :inactive
      deliver_error!(404)
    end

    if data["state"] != "active"
      deliver_error!(
        422,
        message: "You can only update an organization membership's state to 'active'.",
        documentation_url: @documentation_url,
      )
    end

    # Introducing strict validation of the organization-membership.update
    # JSON schema would cause breaking changes for integrators
    # skip_validation until a rollout strategy can be determined
    # see: https://github.com/github/ecosystem-api/issues/1555
    _ = receive_with_schema("organization-membership", "update", skip_validation: true)

    invitation = org.pending_invitation_for(current_user)

    if invitation.present? && !org.two_factor_requirement_met_by?(current_user)
      deliver_error!(
        403,
        message: "The #{org.safe_profile_name} organization requires all members to have two-factor authentication enabled.",
        documentation_url: @documentation_url,
      )
    end

    result = invitation.accept(acceptor: current_user) if invitation.present?
    if result && result.error?
      deliver_error!(
        422,
        message: result.error,
        documentation_url: @documentation_url,
      )
    end

    deliver :org_membership_hash, org, user: current_user
  end

  # list a user's public organizations
  get "/user/:user_id/orgs", operation_id: "orgs/list-for-user" do
    user = find_user!
    control_access :public_site_information,
      resource: Platform::PublicResource.new(resource: user),
      allow_integrations: true,
      allow_user_via_granular_actor: true

    @accepted_scopes = []
    orgs = if user.private_profile_for?(current_user)
      paginate_rel(Organization.none)
    else
      paginate_rel(user.public_organizations.includes(:profile))
    end

    deliver :organization_hash, orgs
  end

  # get an organization
  get "/organizations/:organization_id", operation_id: "orgs/get" do
    @accepted_scopes   = %w(admin:org read:org repo user write:org)

    org = find_org!
    control_access :apps_audited,
      resource: Platform::PublicResource.new(resource: org),
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: false


    # We can rely on these checks for EMU orgs authorization since they have a specific org as resource and will always be performed.
    # Refer https://github.com/github/external-identities/issues/1093

    key = if access_allowed?(:view_org_settings, resource: org, allow_integrations: true, allow_user_via_granular_actor: true)
      :owner_private
    elsif access_allowed?(:get_org_private, resource: org, allow_integrations: true, allow_user_via_granular_actor: true)
      :private
    else
      :full
    end

    include_plan = access_allowed?(:get_org_plan, resource: org, allow_integrations: true, allow_user_via_granular_actor: true)

    deliver :organization_hash,
      org,
      key => true,
      :last_modified => calc_last_modified_for_object(org),
      :plan => include_plan,
      :show_security_feature_auto_enablement_settings => show_security_feature_auto_enablement_settings?(org: org)
  end

  # List the installations the authorized user has access to.
  get "/organizations/:organization_id/installations", operation_id: "orgs/list-app-installations" do
    @accepted_scopes   = %w(admin:org read:org write:org)

    control_access :view_org_installations,
      resource: org = find_org!,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    installations = IntegrationInstallation.user_installable.with_target(org)
    installations = paginate_rel(installations)

    GitHub::PrefillAssociations.prefill_associations(installations, [:target, :event_records, :user_suspended_by, :version, :integration])

    deliver :integration_installations_hash, {
      integration_installations: installations,
      total_count: installations.count,
    }
  end

  post "/organizations/:organization_id/:security_feature/:enablement", operation_id: "orgs/enable-or-disable-security-product-on-all-org-repos" do
    deliver_error!(404) if changeset_active?(:remove_enable_or_disable_security_product_on_all_org_repos)

    deprecated(
      deprecation_date: Time.utc(2024, 7, 22),
      sunset_date: Time.utc(2025, 7, 22),
      info_url: "https://github.blog/changelog/2024-07-22-deprecation-of-api-endpoint-to-enable-or-disable-a-security-feature-for-an-organization/",
    )

    @route_owner = "@github/security_center"
    @documentation_url = "/rest/reference/orgs#enable-or-disable-security-product-on-all-org-repos"

    control_access :manage_org_security_products,
      resource: org = find_org!,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    # This action isn't RESTful and doesn't have a JSON schema.
    # But this is needed by the the linter.
    _ = receive_with_schema("organization", "enable-or-disable-security-feature", skip_validation: true)

    deliver_error!(422, errors: ["Security product toggling is in progress."]) if settings_blocked?(org, security_feature: params[:security_feature])

    security_features = {
      "dependency_graph" => :dependency_graph,
      "dependabot_alerts" => :security_alerts,
      "dependabot_security_updates" => :vulnerability_updates,
      "advanced_security" => :advanced_security,
      "code_scanning_default_setup" => :code_scanning,
      "secret_scanning" => :secret_scanning,
      "secret_scanning_push_protection" => :secret_scanning_push_protection
    }

    if security_features.keys.exclude?(params[:security_feature]) || %w[enable_all disable_all].exclude?(params[:enablement])
      deliver_error! 404
    end

    update_key = { security_features[params[:security_feature]] => params[:enablement] }

    if update_key[:code_scanning] == "enable_all"
      data = receive_with_openapi(required: false, skip_validation: true)
      update_key[:config] = { query_suite: data["query_suite"] } if data["query_suite"].present?
    end

    error_message = UpdateSecuritySettings.perform(org, update_key, actor: current_user, source: "rest-api").try(:fetch, :error, nil)
    if error_message.present?
      # login used for logging therefore safe to use here.
      GitHub.logger.info(error_message, {
        "code.namespace": "Api::Organizations",
        "code.function": "update_tenant_security_and_analysis_configuration",
        "gh.org.id": org.id,
        "gh.org.login": org.login # rubocop:disable GitHub/DoNotAllowLogin
      })
      deliver_error!(422, errors: [error_message])
    end

    GitHub.dogstats.increment("api.orgs.security_product_toggling.success", tags: ["feature:#{params[:security_feature]}", "action:#{params[:enablement]}"])
    deliver_empty status: 204
  end

  # update an organization
  verbs :post, :patch, "/organizations/:organization_id", operation_id: "orgs/update" do
    org = find_org!
    data = receive_with_schema("organization", "update-legacy")

    # If the user is attempting to only modify "Code security" settings,
    # then both admins and users with the "modify_security_products" FGP (aka "Security managers") are authorized.
    #
    # Otherwise, only admins are authorized.
    if security_and_analysis_only_access?(data)
      control_access :manage_org_security_products,
        resource: org,
        allow_integrations: true,
        allow_user_via_granular_actor: true

      if access_allowed?(:update_org, resource: org, allow_integrations: true, allow_user_via_granular_actor: true)
        GitHub.dogstats.increment("organization.edited_by", tags: ["role:organization_administration_writer", "security_and_analysis_only:true"])
      else
        GitHub.dogstats.increment("organization.edited_by", tags: ["role:org_security_products_manager", "security_and_analysis_only:true"])
      end
    else
      control_access :update_org,
        resource: org,
        allow_integrations: true,
        allow_user_via_granular_actor: true

      GitHub.dogstats.increment("organization.edited_by", tags: ["role:organization_administration_writer", "security_and_analysis_only:false"])
    end

    push_protection_custom_link_error = secret_scanning_push_protection_custom_message_error(org: org, data: data)
    if push_protection_custom_link_error.present?
      deliver_error!(
        422,
        message: push_protection_custom_link_error,
        documentation_url: @documentation_url
      )
    end

    keys = [
      :name,
      :email,
      :blog,
      :company,
      :location,
      :twitter_username,
    ]

    # Attributes prefixed with `profile_`.
    attributes = attr(data, *keys, { prefix: "profile_" })

    # Attributes with no prefixes.
    no_prefix_keys = [:has_organization_projects, :has_repository_projects] + COMBINED_SECURITY_AND_ANALYSIS_MAPS.keys
    attributes.update(T.unsafe(self).attr(data, *no_prefix_keys))

    attributes.update(org_permission_extras_attributes(org, data))
    attributes.update(attr(data, :billing_email, :description))

    if update_org_attributes(org, attributes)
      deliver(
        :organization_hash,
        org,
        owner_private: true,
        show_security_feature_auto_enablement_settings: show_security_feature_auto_enablement_settings?(
          api_method: "patch",
          org: org
        )
      )
    else
      deliver_error!(422, errors: org.errors)
    end
  end

  # Delete an organization
  delete "/organizations/:organization_id", operation_id: "orgs/delete" do
    org = find_org!
    deliver_error! 404 if org.deleted?

    control_access \
      :delete_org,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    cannot_delete_reason = org.cannot_delete_reason(current_user)
    case cannot_delete_reason
    when :trusted_oauth_apps_owner
      deliver_error! 403, message: "#{org.safe_profile_name} cannot be deleted. It’s the owner of some trusted applications."
    when :sponsorable
      deliver_error! 403, message: "#{org.safe_profile_name} cannot be deleted. It has a published Sponsors profile that must be unpublished first."
    when :legal_hold
      deliver_error! 403, message: "#{org.safe_profile_name} cannot be deleted."
    when :trade_restrictions
      error_status = changeset_active?(:change_delete_organization_trade_compliance_respose_status) ? 451 : 403
      message = changeset_active?(:change_delete_organization_trade_compliance_respose_status) ? ::TradeControls::Notices.notice_as_plaintext(:org_api_delete_restricted) : ::TradeControls::Notices.notice_as_plaintext(:api_access_restricted)
      deliver_error! error_status, message: message
    when :repo_deletion_not_allowed
      deliver_error! 403, message: "#{org.safe_profile_name} cannot be deleted. Repositories owned by the organization cannot be deleted."
    when :system_account
      deliver_error! 403, message: "#{org.safe_profile_name} cannot be deleted. It is a system account that is important for GitHub to function properly."
    when :spammy
      deliver_error! 403, message: "#{org.safe_profile_name} cannot be deleted. Please contact support if you’d like to delete your organization."
    end

    site_admin_deletion = current_user.site_admin? && !org.adminable_by?(current_user)
    org.soft_delete!(current_user, site_admin_deletion: site_admin_deletion)
    deliver_empty status: 202
  end

  def show_security_feature_auto_enablement_settings?(org:, api_method: "get")
    show_settings = access_allowed?(
      :read_org_security_products,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true
    )

    GitHub.dogstats.increment("orgs.#{api_method}.security_feature_auto_enablement_settings") if show_settings

    show_settings
  end

  # List all organizations
  get "/organizations", operation_id: "orgs/list" do
    control_access :public_site_information,
      # safe Platform::PublicResource usage
      resource: Platform::PublicResource.new, # rubocop:disable GitHub/PublicResource
      allow_integrations: true,
      allow_user_via_granular_actor: true

    cursor = params[:since].to_i || 0
    orgs_scope = Organization.active.where("users.id > ?", cursor).limit(per_page).order("users.id").includes(:profile)
    orgs = if GitHub.enterprise?
      orgs_scope.where("users.login != 'github-enterprise'")
    else
      orgs_scope = orgs_scope.includes(:business)
      orgs_scope.where(business: nil).or(orgs_scope.where(business: { business_type: :default_managed }))
    end

    @links.add_dump_pagination(orgs.last)

    deliver :organization_hash, orgs
  end

  private

  # When enabling a push protection custom link through the API, we have to check whether the request wants custom
  # links to be enabled, whether there is new custom link provided in the request, and the current custom link set for
  # the org in order to check for a possible error to send back to the user.
  def secret_scanning_push_protection_custom_message_error(org:, data:)
    current_custom_message = org.get_push_protection_custom_message
    current_custom_message_nil_or_empty = current_custom_message.nil? || current_custom_message.empty?
    new_custom_message = data["secret_scanning_push_protection_custom_link"]
    new_custom_message_nil_or_empty = new_custom_message.blank?

    custom_message_enabled_by_api = true
    unless changeset_active?(:remove_secret_scanning_custom_link_enablement_field)
      custom_message_enabled_by_api = data["secret_scanning_push_protection_custom_link_enabled"]

      # Checks the case where the user wants to enable custom link, has not provided one in the request, and the org
      # did not previously have one set
      if current_custom_message_nil_or_empty && custom_message_enabled_by_api && new_custom_message_nil_or_empty
        return "\"secret_scanning_push_protection_custom_link\" is required when enabling a push protection custom link."
      end
    end

    # If the user wants to enable a push protection custom message and has provided a link there is an error if the
    # link is not a URL or if the link is greater than our size constraint
    if custom_message_enabled_by_api && !new_custom_message_nil_or_empty
      validity_check = push_protection_custom_message_valid(new_custom_message)
      if !validity_check[:valid] && validity_check[:reason] == :not_url
        return "Verify that \"secret_scanning_push_protection_custom_link\" is a URL."
      end
      if !validity_check[:valid] && validity_check[:reason] == :size
        "\"secret_scanning_push_protection_custom_link\" must be less than #{UpdateSecuritySettings::PUSH_PROTECTION_CUSTOM_MSG_MAX_SIZE} characters."
      end
    end

  end

  # Internal: Organizations whose resources the current requestor is authorized
  # to access. This is especially useful for OAuth applications that want to
  # discover which of the user's organizations the app is authorized to access.
  # While an OAuth app can *see* all of a user's public organizations, it can
  # only *access* an organization if the org's OAuth app policy allows access
  # for the app.
  #
  # Returns an ActiveRecord::Relation, suitable for chaining on additional
  # scopes.
  def accessible_orgs
    scope = if requestor_governed_by_oauth_application_policy?
      current_user.organizations.oauth_app_policy_met_by(current_app_via_oauth)
    else
      current_user.organizations
    end

    return scope unless scope.exists?
    return scope unless ProgrammaticActor::OrganizationFilter.applicable?(current_user)

    accessible_org_ids = ProgrammaticActor::OrganizationFilter.perform(
      actor: current_user, organization_ids: scope.pluck(:id), resource: "members"
    )

    scope.where(id: accessible_org_ids)
  end

  # Internal: Returns a hash of org settings that have been remapped from the request
  def org_permission_extras_attributes(org, data)
    extras_params = {}
    if data.has_key?("default_repository_permission")
      #possible values "none", "read", "write", "admin". v3/schemas/organization.json
      new_permission = data["default_repository_permission"]
      extras_params["default_repository_permission"] = new_permission
    end
    if data.has_key?("members_can_create_repositories")
      extras_params["members_can_create_repositories"] = data["members_can_create_repositories"]
    end
    if data.has_key?("members_allowed_repository_creation_type")
      extras_params["members_allowed_repository_creation_type"] = data["members_allowed_repository_creation_type"]
    end
    if data.has_key?("members_can_create_public_repositories")
      extras_params["members_can_create_public_repositories"] = data["members_can_create_public_repositories"]
    end
    if data.has_key?("members_can_create_private_repositories")
      extras_params["members_can_create_private_repositories"] = data["members_can_create_private_repositories"]
    end
    if data.has_key?("members_can_create_internal_repositories")
      extras_params["members_can_create_internal_repositories"] = data["members_can_create_internal_repositories"]
    end
    if data.has_key?("members_can_create_pages")
      extras_params["members_can_create_pages"] = data["members_can_create_pages"]
    end
    if data.has_key?("members_can_create_public_pages")
      extras_params["members_can_create_public_pages"] = data["members_can_create_public_pages"]
    end
    if data.has_key?("members_can_create_private_pages")
      extras_params["members_can_create_private_pages"] = data["members_can_create_private_pages"]
    end
    if data.has_key?("members_can_fork_private_repositories")
      extras_params["members_can_fork_private_repositories"] = data["members_can_fork_private_repositories"]
    end
    if data.has_key?("web_commit_signoff_required")
      extras_params["web_commit_signoff_required"] = data["web_commit_signoff_required"]
    end
    if data.has_key?("disallow_insecure_two_factor_methods")
      extras_params["disallow_insecure_two_factor_methods"] = data["disallow_insecure_two_factor_methods"]
    end
    if data.has_key?("deploy_keys_enabled_for_repositories")
      extras_params["deploy_keys_enabled_for_repositories"] = data["deploy_keys_enabled_for_repositories"]
    end
    extras_params
  end

  # Internal: Updates an organizations attributes.
  # If the attribute default_repository_permission is included it will queue an async job
  # to update the permission settings for every org owned repo.
  #
  # Returns true or false
  def update_org_attributes(org, attributes)
    configurable_settings = {}

    if attributes.key?("default_repository_permission")
      deliver_updating_default_repo_permission_error! if org.updating_default_repository_permission?
      configurable_settings[:default_repository_permission] = attributes.delete("default_repository_permission")
    end

    if attributes.key?("members_can_create_repositories")
      configurable_settings[:can_create_repos] = attributes.delete("members_can_create_repositories")
    end

    if attributes.key?("disallow_insecure_two_factor_methods")
      if org.two_factor_disallowed_methods_policy?
        deliver_error!(422, errors: "disallow_insecure_two_factor_methods is being configured by your enterprise and cannot be modified by the organization.")
      end
      configurable_settings[:disallow_insecure_two_factor_methods] = attributes.delete("disallow_insecure_two_factor_methods")
    end

    if attributes.key?("members_allowed_repository_creation_type")
      if attributes["members_allowed_repository_creation_type"] == "private"
        unless org.can_restrict_only_public_repo_creation?
          deliver_error!(422, errors: '"private" is not a valid value for members_allowed_repository_creation_type in this organization.')
        end
      end
      configurable_settings[:members_allowed_repository_creation_type] = attributes.delete("members_allowed_repository_creation_type")
    end

    if attributes.key?("members_can_fork_private_repositories")
      deliver_error!(422, errors: "Forking policy has been set by enterprise administrators.") if org&.business&.allow_private_repository_forking_policy?
    end

    if attributes.key?("deploy_keys_enabled_for_repositories")
      # If the enterprise has set the deploy key policy, the organization cannot modify it.
      if org.deploy_key_policy_inherited?
        deliver_error!(422, errors: "Deploy key policy has been set by enterprise administrators and cannot be modified by the organization.")
      end
      configurable_settings[:deploy_keys_enabled_for_repositories] = attributes.delete("deploy_keys_enabled_for_repositories")
    end

    %w[members_can_create_public_repositories
      members_can_create_private_repositories
      members_can_create_internal_repositories
    ].each do |attribute|
      if attributes.key?(attribute)
        deliver_error!(422, errors: "Private-only repository creation policy is not allowed for this organization.") if setting_invalid_private_only_creation_policy?(org, attributes)
        if !org.supports_internal_repositories? && attribute == "members_can_create_internal_repositories"
          deliver_error!(422, errors: "This organization does not support internal repositories.")
        end
        configurable_settings[attribute.to_sym] = attributes.delete(attribute)
      end
    end

    if attributes.key?("secret_scanning_validity_checks_enabled")
      validity_checks = SecretScanning::Features::Org::ValidityChecks.new(org)
      if validity_checks.enabled_by_owner?
        deliver_error!(422, errors: "Validity checks has been set by enterprise administrators.")
      end
    end

    if attributes.key?("members_can_create_pages")
      configurable_settings[:members_can_create_pages] = attributes.delete("members_can_create_pages")
    end

    if attributes.key?("members_can_create_public_pages")
      configurable_settings[:members_can_create_public_pages] = attributes.delete("members_can_create_public_pages")
    end

    if attributes.key?("members_can_create_private_pages")
      configurable_settings[:members_can_create_private_pages] = attributes.delete("members_can_create_private_pages")
    end

    if attributes.key?("members_can_fork_private_repositories")
      configurable_settings[:members_can_fork_private_repositories] = attributes.delete("members_can_fork_private_repositories")
    end

    if attributes.key?("web_commit_signoff_required")
      configurable_settings[:web_commit_signoff_required] = attributes.delete("web_commit_signoff_required")
    end

    BOOLEAN_SECURITY_AND_ANALYSIS_SETTINGS_PUBLIC_TO_INTERNAL_NAMES_MAP.keys.each do |setting_name|
      if attributes.key?(setting_name)
        configurable_settings[setting_name] = attributes.delete(setting_name)
      end
    end

    NON_BOOLEAN_SECURITY_AND_ANALYSIS_SETTINGS_PUBLIC_TO_INTERNAL_NAMES_MAP.keys.each do |setting_name|
      if attributes.key?(setting_name)
        configurable_settings[setting_name] = attributes.delete(setting_name)
      end
    end

    update_org_attributes_and_configurables(org, attributes, configurable_settings)
  end

  private def setting_invalid_private_only_creation_policy?(org, attributes)
    return false if org.can_restrict_only_public_repo_creation?
    new_public_allowed = if attributes.key?("members_can_create_public_repositories")
      attributes["members_can_create_public_repositories"]
    else
      org.members_can_create_public_repositories?
    end
    new_private_allowed = if attributes.key?("members_can_create_private_repositories")
      attributes["members_can_create_private_repositories"]
    else
      org.members_can_create_private_repositories?
    end
    return true if !new_public_allowed && new_private_allowed
    false
  end

  # Internal: update the attributes and settings stored via Configurable.
  # Supported Configurable settings:
  #  - default_repository_permission
  #  - can_create_repos
  #  - members_can_create_public_repositories
  #  - members_can_create_private_repositories
  #  - members_can_create_internal_repositories
  #
  # Returns: true or false, based on attributes update also. Configurable updates do
  # not return a success/failure, so we assume they succeed (unless an exception is raised)
  def update_org_attributes_and_configurables(org, attributes, configurable_settings)
    success = T.let(false, T::Boolean)

    Organization.transaction do
      if success = org.update(attributes)
        if configurable_settings.key?(:default_repository_permission)
          org.update_default_repository_permission(configurable_settings[:default_repository_permission],
                                                   actor: current_user)
        end
        if configurable_settings.key?(:can_create_repos)
          org.update_members_can_create_repositories(configurable_settings[:can_create_repos].to_s,
                                                     actor: current_user)
        end
        if configurable_settings.key?(:members_allowed_repository_creation_type)
          org.update_members_can_create_repositories(
            configurable_settings[:members_allowed_repository_creation_type].to_s,
            actor: current_user,
          )
        end
        granular_permissions = [:members_can_create_public_repositories, :members_can_create_private_repositories, :members_can_create_internal_repositories]
        if granular_permissions.any? { |k| configurable_settings.key?(k) }
          org.allow_members_can_create_repositories_with_visibilities(
            public_visibility: configurable_settings[:members_can_create_public_repositories],
            private_visibility: configurable_settings[:members_can_create_private_repositories],
            internal_visibility: configurable_settings[:members_can_create_internal_repositories],
            actor: current_user,
          )
        end
      end
      if configurable_settings.key?(:members_can_create_pages)
        org.update_members_create_pages_permission(
          enabled: configurable_settings[:members_can_create_pages],
          actor: current_user,
        )
      end

      if GitHub.flipper[:private_pages_org_toggle].enabled?(org)
        if configurable_settings.key?(:members_can_create_public_pages)
          org.update_members_create_public_pages_permission(
            enabled: configurable_settings[:members_can_create_public_pages],
            actor: current_user,
          )
        end
        if configurable_settings.key?(:members_can_create_private_pages)
          org.update_members_create_private_pages_permission(
            enabled: configurable_settings[:members_can_create_private_pages],
            actor: current_user,
          )
        end
      end

      if configurable_settings.key?(:members_can_fork_private_repositories)
        allow_forks = configurable_settings[:members_can_fork_private_repositories]

        if allow_forks
          org.allow_private_repository_forking(actor: current_user)
        else
          org.block_private_repository_forking(actor: current_user)
        end
      end

      if configurable_settings.key?(:web_commit_signoff_required)
        web_commit_signoff_required = configurable_settings[:web_commit_signoff_required]

        if web_commit_signoff_required
          org.enable_dco_signoff_for_all(actor: current_user)
        else
          org.reset_dco_signoff_for_all(actor: current_user)
        end
      end

      if configurable_settings.key?(:deploy_keys_enabled_for_repositories)
        enable_deploy_key_policy = configurable_settings[:deploy_keys_enabled_for_repositories]
        if enable_deploy_key_policy
          org.enable_deploy_key_policy(actor: current_user)
        else
          org.disable_deploy_key_policy(actor: current_user)
        end
      end
    end

    # enqueues a job, do outside of transaction
    if configurable_settings.key?(:disallow_insecure_two_factor_methods)
      disallow_insecure_two_factor_methods = configurable_settings[:disallow_insecure_two_factor_methods]

      if disallow_insecure_two_factor_methods
        EnforceTwoFactorRequirementOnOrganizationJob.perform_later(org, current_user, disallowed_methods: [Configurable::TwoFactorDisallowedMethods::INSECURE])
      else
        org.remove_disallowed_two_factor_method(method: :insecure, actor: current_user, log_event: true)
      end
    end

    return success if !success

    # Because update_tenant_security_and_analysis_configuration enqueues background jobs, we want to do this after
    # the above transaction; in case the transaction fails, we don't want background jobs enqueued.
    error_message = update_tenant_security_and_analysis_configuration(
      org,
      settings: configurable_settings,
      should_remove_custom_link_enablement_field: changeset_active?(:remove_secret_scanning_custom_link_enablement_field),
    )
    if error_message.present?
      # login used for logging therefore safe to use here.
      GitHub.logger.info(error_message, {
        "code.namespace": "Api::Organizations",
        "code.function": "update_tenant_security_and_analysis_configuration",
        "gh.org.id": org.id,
        "gh.org.login": org.login # rubocop:disable GitHub/DoNotAllowLogin
      })

      return false
    end

    true
  end

  def deliver_updating_default_repo_permission_error!
    deliver_error!(409, errors: <<~STR.tr("\n", " ")
        Currently updating default_repository_permission. Further changes will be ignored until update is complete.
        If you wish to update other settings, please remove default_repository_permission from your request.
      STR
    )
  end
end
