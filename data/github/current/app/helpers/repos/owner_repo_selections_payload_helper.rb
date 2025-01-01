# typed: true
# frozen_string_literal: true

module Repos::OwnerRepoSelectionsPayloadHelper
  extend T::Helpers

  include Kernel
  include RepositoriesHelper
  include Repos::GitHubEnterpriseHelper
  include Orgs::CustomPropertiesHelper

  FORK_ALREADY_EXISTS = "(fork already exists)"
  REPOSITORY_ALREADY_EXISTS = "(repository already exists)"
  DISABLED_BY_POLICY = "(disabled by policy)"
  NO_FORKING_INTERNAL_REPO_OUTSIDE_OF_ENTERPRISE = "(cannot fork internal repositories outside enterprise)"

  ME_PARAM = "@me".freeze

  # Return initial items payload for Create, Transfer, Import pages.
  # When `forking_repo` is provided, the items payload will be for the Fork page.
  sig do
    params(
      cap_filter: ConditionalAccess::Web::Filter,
      user: User,
      forking_repo: T.nilable(Repository)
    ).returns(T.nilable(T::Array[T.any(PayloadType, OwnerItemPayloadType)]))
  end
  def initial_owner_items_payload(cap_filter, user, forking_repo = nil)
    return nil if user.organizations.size > Repositories::CreateView::ORG_COUNT_DEFER_LIMIT

    owners_hash = forking_repo ? accessible_fork_owners_hash(cap_filter, user, forking_repo) : accessible_owners_hash(cap_filter, user)
    owner_items_payload(owners_hash, user)
  end

  # Gets the owners that the user is allowed to see when creating a repo.
  # Includes the organizations the user is allowed to see, plus the user themselves as the first entry.
  # Returns a hash with the User or Organization as the keys, and the org_info as the value.
  sig do
    params(
      cap_filter: ConditionalAccess::Web::Filter,
      user: User,
    ).returns(T::Hash[T.any(Organization, User), T.untyped])
  end
  def accessible_owners_hash(cap_filter, user)
    { user => org_info_for_user(user) }.merge(accessible_orgs_hash(cap_filter, user))
  end

  # Gets the owners that the user is allowed to see when forking a repo.
  # Includes the organizations the user is allowed to see, plus the user themselves as the first entry.
  # Returns a hash with the User or Organization as the keys, and the org_info as the value.
  sig do
    params(
      cap_filter: ConditionalAccess::Web::Filter,
      user: User,
      repo: Repository,
    ).returns(T::Hash[T.any(Organization, User), T.untyped])
  end
  def accessible_fork_owners_hash(cap_filter, user, repo)
    return {} if repo.internal_fork?

    orgs_hash = accessible_orgs_hash(cap_filter, user)
    orgs_hash.each do |org, info|
      org_fork_allowed = org.fork_allowed?(repo: repo, user: user)
      info[:custom_disabled_message] = DISABLED_BY_POLICY unless org_fork_allowed
      if !org_fork_allowed && repo.allow_private_repository_forking_to_any_location? && repo.internal?
        # This is a special case to specifically address the fact that we don't allow forking internal repos outside of enterprise
        info[:custom_disabled_message] = NO_FORKING_INTERNAL_REPO_OUTSIDE_OF_ENTERPRISE
      end
      info[:disabled] = true unless org.can_create_repository?(user, visibility: repo.visibility)
    end

    { user => org_info_for_user(user, repo) }.merge(orgs_hash)
  end

  # Gets the payloads of the owner items to populate the dropdown.
  # It includes the user, plus the organizations they are allowed to see.
  # Returns an array with the payload, the user being the first entry.
  sig do
    params(
      owners_hash: T::Hash[T.any(Organization, User), T.untyped],
      user: User,
    ).returns(T::Array[OwnerItemPayloadType])
  end
  def owner_items_payload(owners_hash, user)
    owners_hash.map do |org, info|
      owner_item_payload(org, user, info)
    end
  end

  sig do
    params(
      initial_owner: T.nilable(T.any(User, Organization)),
      user: User,
      repo: T.nilable(Repository),
      transfer: T::Boolean
    ).returns(T.nilable(PayloadType))
  end
  def initial_owner_selection_payload(initial_owner, user, repo = nil, transfer: false)
    owner_repo_payload(
      initial_owner,
      user,
      org_info_hash(initial_owner, user),
      repo,
      should_instrument_installable_apps: !transfer,
      transfer: transfer
    )
  end

  def org_info_hash(owner, user)
    return nil unless owner&.organization?

    ability = Ability.find_by(
      actor_id: user.ability_id,
      actor_type: user.ability_type,
      subject_type: "Organization",
      subject_id: owner.id,
      priority: Ability.priorities[:direct],
    )
    action = ability&.action&.to_sym || :read

    user.organization_hash(owner, action)
  end

  # Gets the initial owner based on provided param or the default owner for the page
  sig do
    params(
      owner_param: T.nilable(String),
      cap_filter: ConditionalAccess::Web::Filter,
      user: User,
      current_organization: T.nilable(Organization)
    ).returns(T.nilable(PayloadType))
  end
  def initial_owner_or_default_payload(owner_param, cap_filter, user, current_organization)
    payload = initial_owner_from_param_payload(owner_param, cap_filter, user)
    return payload if payload

    initial_owner = default_owner_initial_selection(user, current_organization || user)
    initial_owner_selection_payload(initial_owner, user)
  end

  # Gets the initial owner from the provided param or nil
  sig do
    params(
      owner_param: T.nilable(String),
      cap_filter: ConditionalAccess::Web::Filter,
      user: User,
      repo: T.nilable(Repository),
      transfer: T::Boolean,
    ).returns(T.nilable(PayloadType))
  end
  def initial_owner_from_param_payload(owner_param, cap_filter, user, repo = nil, transfer: false)
    return unless owner_param.present?

    if owner_param == user.display_login || ME_PARAM.casecmp?(owner_param)
      return initial_owner_selection_payload(user, user, repo, transfer: transfer)
    end

    org = find_org_accessible_by_user(owner_param, cap_filter, user)

    initial_owner_selection_payload(org, user, repo, transfer: transfer)
  end

  private

  sig { params(org_login: String, cap_filter: ConditionalAccess::Web::Filter, user: User).returns(T.nilable(Organization)) }
  def find_org_accessible_by_user(org_login, cap_filter, user)
    org = Organization.find_by_login(org_login)
    return unless org
    return unless cap_filter.authorized_resources(org).present?

    org if org.direct_or_team_member?(user) ||
      org.adminable_by?(user) ||
      org.billing_manager?(user)
  end

  # Returns the payload for a specific user or org.
  sig do
    params(
      selection: T.nilable(T.any(User, Organization)),
      current_user: User,
      org_info: T.nilable(T::Hash[Symbol, T.untyped]),
      repo: T.nilable(Repository),
      should_instrument_installable_apps: T::Boolean,
      transfer: T::Boolean
    )
    .returns(T.nilable(PayloadType))
  end
  def owner_repo_payload(selection, current_user, org_info, repo = nil, should_instrument_installable_apps:, transfer: false)
    return if selection.nil?

    allow_public_repos = !org_info || org_info[:allow_public_repos]

    is_organization = selection.organization?

    displayed_visibilities = %w[public internal private]

    public_repositories_available = current_user.public_repositories_available? && GitHub.public_repositories_available?

    if !public_repositories_available
      displayed_visibilities.delete("public")
    end

    business_name = org_info && selection.business&.safe_profile_name

    if !business_name
      displayed_visibilities.delete("internal")
    end

    adminable_by_current_user = selection.adminable_by?(current_user)

    custom_disabled_message = org_info ? org_info[:custom_disabled_message] : custom_disabled_message_for_user(current_user)
    disabled = custom_disabled_message.present? || (org_info && org_info[:access] == :read)

    required_definitions = []
    editable_definitions_names = []
    initial_properties_values = nil

    if selection.organization?
      org = T.cast(selection, Organization)

      if transfer
        raise ArgumentError, "Repo is required when getting owner details for the transfer" if repo.nil?
        requires_request = RepositoryTransfer.requires_transfer_request?(
          target: org,
          requester: current_user,
          repository_visibility: repo.visibility
        )

        required_definitions = requires_request ? [] : required_definitions_for(org)
        editable_definitions_names = org.can_edit_organization_custom_properties_values?(current_user) ? required_definitions.map(&:property_name) : []
      else
        required_definitions = required_definitions_for(org)
        editable_definitions_names = if org.can_edit_organization_custom_properties_values?(current_user)
          required_definitions.map(&:property_name)
        else
          required_definitions.filter_map do |d|
            editable_by_repo_actor = Repositories.domain.custom_properties.editable_by_repo_actors?(d)
            d.property_name if editable_by_repo_actor
          end
        end
      end

      if repo
        same_business_transfer = repo.owner&.business.present? && selection.business.present? && repo.owner&.business.id == selection.business.id
        if same_business_transfer
          required_business_properties_names = required_definitions.filter_map do |definition|
            definition.property_name if definition.business_source_type?
          end.to_set

          initial_properties_values = Repositories.domain.custom_properties
            .repo_properties([repo], :effective).fetch(repo, {})
            .select { |property_name| required_business_properties_names.include?(property_name) }
        end
      end
    end

    repo_for_ruleset_evaluation =
      if repo
        repo
      else
        repo = selection.repositories.build(name: "")
      end

    if !disabled
      rule_result = RulesEngine::RepositoryActionEvaluator.check_repo_create(repo_for_ruleset_evaluation, current_user, persist_results: false)
      if rule_result&.failed_rule_types(filter_bypassable: true)&.include?("repository_create")
        disabled = true
        custom_disabled_message = DISABLED_BY_POLICY
      end
    end

    {
      name: selection.display_login,
      avatarUrl: selection.primary_avatar_url,
      businessName: business_name,
      displayedVisibilities: displayed_visibilities,
      defaultVisibility: selection.default_repo_visibility,
      publicRestrictedByPolicy: is_organization && !allow_public_repos,
      internalRestrictedByPolicy: business_name && !org_info[:allow_internal_repos],
      privateRestrictedByPolicy: (org_info && !org_info[:allow_private_repos]),
      publicRestrictedByRulesets: !repo_for_ruleset_evaluation.can_change_repo_visibility_with_rules?(current_user, "public"),
      internalRestrictedByRulesets: !repo_for_ruleset_evaluation.can_change_repo_visibility_with_rules?(current_user, "internal"),
      privateRestrictedByRulesets: !repo_for_ruleset_evaluation.can_change_repo_visibility_with_rules?(current_user, "private"),
      privateRestrictedByPlan: is_organization && !(selection.can_add_private_repo? && selection.restriction_tier_allows_feature?(type: :repository)),
      hasTradeRestrictions: selection.has_any_trade_restrictions?,
      adminableByCurrentUser: is_organization && adminable_by_current_user,
      isOrganization: is_organization,
      disabled: disabled,
      customDisabledMessage: custom_disabled_message,
      defaultNewRepoBranch: selection.default_new_repo_branch,
      defaultBranchSettingsUrl: show_default_branch_settings_link_for?(selection) ? default_branch_settings_url_for(selection) : nil,
      enterpriseManagedUserEnabled: selection.is_a?(Organization) ? selection.enterprise_managed_user_enabled? : false,
      installableApps: populate_installable_apps(current_user, selection.installable_apps, should_instrument_installable_apps),
      requiredDefinitions: definitions_payload(required_definitions),
      initialPropertyValues: initial_properties_values,
      overRepositoryLimit: RepositoryLimit.new(selection).hard_limited?,
      editableDefinitionNames: editable_definitions_names
    }
  end

  sig { params(org: Organization).returns(T::Array[CustomProperties::IPropertyDefinition]) }
  def required_definitions_for(org)
    Repositories.domain.custom_properties.get_definitions(org).filter { |definition| definition.required }
  end

  # Returns the payload for an owner item, including only minimum data for display
  # It returns a payload in camelCase naming, so no need to camelize the result.
  sig do
    params(
      owner: T.any(User, Organization),
      current_user: User,
      org_info: T.nilable(T::Hash[Symbol, T.untyped])
    )
    .returns(OwnerItemPayloadType)
  end
  def owner_item_payload(owner, current_user, org_info)
    custom_disabled_message = org_info && org_info[:custom_disabled_message]
    disabled = org_info ? (org_info[:disabled] || org_info[:access] == :read) : false

    if !disabled
      rule_result = RulesEngine::RepositoryActionEvaluator.check_repo_create(owner.repositories.build(name: ""), current_user, persist_results: false)
      if rule_result&.failed_rule_types(filter_bypassable: true)&.include?("repository_create")
        disabled = true
        custom_disabled_message = DISABLED_BY_POLICY
      end
    end

    {
      name: owner.display_login,
      avatarUrl: owner.primary_avatar_url,
      disabled: custom_disabled_message.present? || disabled,
      customDisabledMessage: custom_disabled_message || "",
      isOrganization: owner.organization?,
      businessName: owner.business&.safe_profile_name
    }
  end

  def populate_installable_apps(current_user, installable_apps, should_instrument_installable_apps)
    instrument_marketplace_quick_install_view(current_user, installable_apps) if should_instrument_installable_apps
    installable_apps.map do |app, auto_install|
      {
        id: app.id,
        bgcolor: app.bgcolor,
        primaryAvatarUrl: app.primary_avatar_url,
        name: app.name,
        normalizedShortDescription: app.normalized_short_description,
        autoInstall: auto_install
      }
    end
  end

  sig do
    params(
      cap_filter: ConditionalAccess::Web::Filter,
      user: User,
    ).returns(T::Hash[Organization, T.untyped])
  end
  def accessible_orgs_hash(cap_filter, user)
    all_orgs_info_hash = user.organizations_info_sorted_hash

    Configurable.preload_configuration(all_orgs_info_hash.keys)

    allowed_orgs = cap_filter
      .authorized(all_orgs_info_hash.keys)
      .resources
      .select { |organization| !organization.has_sdn_new_org_with_free_plan_restriction? }

    all_orgs_info_hash.select { |org, _| allowed_orgs.include?(org) }
  end

  sig { params(user: User, forking_repo: T.nilable(Repository)).returns(T::Hash[Symbol, T.untyped]) }
  def org_info_for_user(user, forking_repo = nil)
    custom_disabled_message = if forking_repo
      custom_disabled_message_for_forking_user(user, forking_repo)
    else
      custom_disabled_message_for_user(user)
    end

    {
      access: :admin,
      allow_internal_repos: true,
      allow_private_repos: true,
      allow_public_repos: true,
      custom_disabled_message: custom_disabled_message,
    }
  end

  sig { params(user: User).returns(T.nilable(String)) }
  def custom_disabled_message_for_user(user)
    DISABLED_BY_POLICY if restrict_create_repositories_in_personal_namespace?(user)
  end

  sig { params(user: User, repo: Repository).returns(T.nilable(String)) }
  def custom_disabled_message_for_forking_user(user, repo)
    return DISABLED_BY_POLICY if !user.fork_allowed?(repo) || restrict_create_repositories_in_personal_namespace?(user)
    return REPOSITORY_ALREADY_EXISTS if repo.owner == user
    return FORK_ALREADY_EXISTS if repo.network&.repositories&.where(owner: user)&.exists?
    nil
  end

  PayloadType = T.type_alias do
    {
      name: String,
      avatarUrl: String,
      businessName: T.untyped,
      displayedVisibilities: T.untyped,
      defaultVisibility: T.nilable(String),
      publicRestrictedByPolicy: T.untyped,
      internalRestrictedByPolicy: T.untyped,
      privateRestrictedByPolicy: T.untyped,
      publicRestrictedByRulesets: T.untyped,
      internalRestrictedByRulesets: T.untyped,
      privateRestrictedByRulesets: T.untyped,
      privateRestrictedByPlan: T.untyped,
      hasTradeRestrictions: T.untyped,
      adminableByCurrentUser: T.untyped,
      isOrganization: T.untyped,
      disabled: T.untyped,
      customDisabledMessage: T.untyped,
      defaultNewRepoBranch: String,
      defaultBranchSettingsUrl: T.nilable(String),
      enterpriseManagedUserEnabled: T.untyped,
      installableApps: T::Array[T.untyped],
      initialPropertyValues: T.nilable(T::Hash[String, T.nilable(CustomProperties::PropertyValue)]),
      requiredDefinitions: T::Array[T.untyped],
      overRepositoryLimit: T::Boolean,
      editableDefinitionNames: T::Array[String]
    }
  end

  OwnerItemPayloadType = T.type_alias do
    {
      name: String,
      avatarUrl: String,
      disabled: T::Boolean,
      customDisabledMessage: String,
      isOrganization: T::Boolean,
      businessName: T.nilable(String)
    }
  end
end
