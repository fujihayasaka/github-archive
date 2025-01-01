# typed: true
# frozen_string_literal: true

module Repository::PermissionsDependency
  extend T::Helpers

  requires_ancestor { Repository }

  # Only certain resources have been updated with Authzd support, currently contents and pull_requests
  # https://github.com/github/authzd/blob/0aca7468c4184cfad3c38fba6057b9e7a23d2916/config/policies/repository.json#L224-L405
  # but check for these policies on master as they may have since been updated without this comment being edited.
  def async_can_read_resource?(actor, resource_name, context = {})
    return Promise.resolve(false) if unpersisted?
    return Promise.resolve(false) if Repository::Resources::WRITEONLY_SUBJECT_TYPES.include?(resource_name)

    business_promise = if actor.respond_to?(:async_enterprise_managed_business)
      actor.async_enterprise_managed_business
    else
      Promise.resolve(nil)
    end

    business_promise.then do |enterprise_managed_business|
      context.merge!({
        "action.programmatic_resource_type" => resource_name,
        "actor.include_business_user_account" => enterprise_managed_business && GitHub.flipper[:emu_vss_business].enabled?(enterprise_managed_business),
        "considers_anonymous" => true,
        "private_mode_enabled" => GitHub.private_mode_enabled?,
      })

      async_authorized_via_policy?(actor, "read_repo_#{resource_name}", context)
    end
  end

  def async_can_write_resource?(actor, resource_name)
    return Promise.resolve(false) if unpersisted? || !actor
    return Promise.resolve(false) if Repository::Resources::READONLY_SUBJECT_TYPES.include?(resource_name)

    async_authorized_via_policy?(
      actor,
      "write_repo_#{resource_name}",
      {
        "action.programmatic_resource_type" => resource_name,
        "subject.accepts_public_push" => public_push?
      }
    )
  end

  # Public: Checks if a user is authorized to toggle page settings.
  #
  # user - The User to check
  #
  # Returns a Promise<Boolean>
  def async_can_toggle_page_settings?(user)
    return Promise.resolve(false) unless user

    async_authorized_via_policy?(user, :manage_settings_pages)
  end

  # Public: Checks if a user can toggle merge settings for this repo.
  #
  # user - The User to check.
  #
  # Returns a Promise<Boolean>.
  def async_can_toggle_merge_settings?(user)
    return Promise.resolve(false) unless user

    async_authorized_via_policy?(user, :manage_settings_merge_types)
  end

  # Public: Is a user able to set social preview for this repo?
  #
  # user - The User to check.
  # allow_site_admin: if user is site admin, the operation will be granted
  #                   used through stafftools - site admins can change social preview there
  #
  # Returns a Promise<Boolean>.
  def async_can_set_social_preview?(user, allow_site_admin: false)
    return Promise.resolve(false) unless user

    async_authorized_via_policy?(user, :set_social_preview, { considers_site_admin: allow_site_admin })
  end

  # Public: Can a user set interaction limits in this repository?
  #
  # actor - The User to check permissions for.
  #
  # Returns a Promise<Boolean>.
  def async_can_set_interaction_limits?(actor)
    return Promise.resolve(false) unless actor.present?

    # we have to preload the parent here because it is used by `owning_organization_id`,
    # which is called by `subject_attributes`.
    async_parent.then do
      async_authorized_via_policy?(actor, :set_interaction_limits)
    end
  end

  def can_set_interaction_limits?(actor)
    async_can_set_interaction_limits?(actor).sync
  end

  # Public: Can a user read interaction limits in this repository?
  #
  # actor - The User to check permissions for.
  #
  # Returns a Promise<Boolean>.
  def async_can_read_interaction_limits?(actor)
    return Promise.resolve(false) unless actor.present?

    if actor.can_have_granular_permissions?
      resources.administration.async_readable_by?(actor)
    else
      async_can_set_interaction_limits?(actor)
    end
  end

  def can_read_interaction_limits?(actor)
    async_can_read_interaction_limits?(actor).sync
  end

  # Public: Can a user manage webhooks in this repository?
  #
  # actor - The User to check permissions for.
  # site_admin - Consider Site Admins?
  #
  # Returns a Promise<Boolean>.
  def async_can_manage_webhooks?(actor, site_admin: false)
    return Promise.resolve(false) unless actor.present?

    async_authorized_via_policy?(actor, :manage_webhooks, { considers_site_admin: site_admin })
  end

  # Public: Can a user edit branch protections in this repository?
  #
  # actor - The User to check permissions for.
  #
  # Returns a Promise<Boolean>.
  def async_can_edit_repo_protections?(actor)
    return Promise.resolve(false) unless actor.present?

    if actor.can_have_granular_permissions?
      Promise.resolve(self.resources.administration.writable_by?(actor))
    else
      async_authorized_via_policy?(actor, :edit_repo_protections)
    end
  end

  # Public: Can a user manage deploy keys this repository?
  #
  # actor - The User to check permissions for.
  #
  # Returns a Promise<Boolean>.
  def async_can_manage_deploy_keys?(actor)
    return Promise.resolve(false) unless actor.present?

    async_owner.then do |_owner|
      async_authorized_via_policy?(actor, :manage_deploy_keys)
    end
  end

  def async_can_programmatic_actor_manage_deploy_keys?(actor, programmatic_access_level)
    return Promise.resolve(false) unless actor.present?

    async_owner.then do |_owner|
      async_authorized_via_policy?(
        actor,
        :manage_deploy_keys,
        { "action.programmatic_access_level": programmatic_access_level }
      )
    end
  end

  # Public: Can the user edit the description for this repository
  #
  # Returns Boolean
  def can_edit_repo_metadata?(user)
    async_can_edit_repo_metadata?(user).sync
  end

  def async_can_edit_repo_metadata?(user)
    return Promise.resolve(false) unless user
    async_authorized_via_policy?(user, :edit_repo_metadata)
  end

  def can_manage_topics?(user)
    async_can_manage_topics?(user).sync
  end

  def async_can_manage_topics?(user)
    return Promise.resolve(false) unless user
    async_authorized_via_policy?(user, :manage_topics)
  end

  def async_can_toggle_wiki?(user)
    return Promise.resolve(false) unless user
    async_authorized_via_policy?(user, :manage_settings_wiki)
  end

  def can_toggle_wiki?(user)
    async_can_toggle_wiki?(user).sync
  end

  # Public: Can a user enable and disable projects in this repository?
  #
  # actor - The User to check permissions for.
  #
  # Returns a Promise<Boolean>.
  def async_can_toggle_projects?(actor)
    return Promise.resolve(false) unless actor.present?
    async_authorized_via_policy?(actor, :manage_settings_projects)
  end

  def async_can_edit_announcement_banners?(actor)
    return Promise.resolve(false) unless actor.present?

    # matches the manage-repo-settings authzd policy
    async_authorized_via_policy?(actor, :edit_repo_announcement_banners)
  end

  # Check if the user has the repo-level FGP for editing custom property values. If you need to check
  # whether the user can edit a specific value for a specific repo at all, use
  # Repository::Domain::CustomProperties domain accessor
  def async_can_edit_custom_property_values_as_repo_actor?(actor)
    return Promise.resolve(false) unless actor.present?

    async_authorized_via_policy?(
      actor,
      :edit_repo_custom_properties_values,
      { "action.programmatic_access_level": Permission.actions[:write] }
    )
  end

  def can_write_repository_actions_settings?(actor)
    async_can_write_repository_actions_settings?(actor).sync
  end

  # Check to see if the user satisfies the write_repository_actions_settings Authzd policy with write access
  def async_can_write_repository_actions_settings?(actor)
    return Promise.resolve(false) unless GitHub.flipper[:repo_ci_cd_admin].enabled?(actor) || GitHub.flipper[:repo_ci_cd_admin].enabled?(self.owner)
    return Promise.resolve(false) unless actor.present?
    async_authorized_via_policy?(actor, :write_repository_actions_settings)
  end

  def can_write_repository_actions_environments?(actor)
    async_can_write_repository_actions_environments?(actor).sync
  end

  # Check to see if the user satisfies the write_repository_actions_environments Authzd policy with write access
  def async_can_write_repository_actions_environments?(actor)
    return Promise.resolve(false) unless GitHub.flipper[:repo_ci_cd_admin].enabled?(actor) || GitHub.flipper[:repo_ci_cd_admin].enabled?(self.owner)
    return Promise.resolve(false) unless actor.present?

    async_authorized_via_policy?(actor, :write_repository_actions_environments)
  end

  def can_write_repository_actions_runners?(actor)
    async_can_write_repository_actions_runners?(actor).sync
  end

  # Check to see if the user satisfies the write_repository_actions_runners Authzd policy with write access
  def async_can_write_repository_actions_runners?(actor)
    return Promise.resolve(false) unless GitHub.flipper[:repo_ci_cd_admin].enabled?(actor) || GitHub.flipper[:repo_ci_cd_admin].enabled?(self.owner)
    return Promise.resolve(false) unless actor.present?

    async_authorized_via_policy?(actor, :write_repository_actions_runners)
  end

  def can_write_repository_actions_secrets?(actor)
    async_can_write_repository_actions_secrets?(actor).sync
  end

  # Check to see if the user satisfies the write_repository_actions_secrets Authzd policy with write access
  def async_can_write_repository_actions_secrets?(actor)
    return Promise.resolve(false) unless GitHub.flipper[:repo_ci_cd_admin].enabled?(actor) || GitHub.flipper[:repo_ci_cd_admin].enabled?(self.owner)
    return Promise.resolve(false) unless actor.present?

    Platform::Loaders::Permissions::BatchAuthorize.load(
      action: :write_repository_actions_secrets,
      actor: actor,
      subject: self,
    ).then do |result|
      result.allow?
    end
  end

  def can_write_repository_actions_variables?(actor)
    async_can_write_repository_actions_variables?(actor).sync
  end

  # Check to see if the user satisfies the write_repository_actions_variables Authzd policy with write access
  def async_can_write_repository_actions_variables?(actor)
    return Promise.resolve(false) unless GitHub.flipper[:repo_ci_cd_admin].enabled?(actor) || GitHub.flipper[:repo_ci_cd_admin].enabled?(self.owner)
    return Promise.resolve(false) unless actor.present?

    Platform::Loaders::Permissions::BatchAuthorize.load(
      action: :write_repository_actions_variables,
      actor: actor,
      subject: self,
    ).then do |result|
      result.allow?
    end
  end


  # These are the FGPs that grant access to bits of the repository settings page, for both public or private repos.
  # These are used to decide whether to render the settings tab or not
  REPOSITORY_SETTINGS_FGPS = [
    :manage_settings_wiki,
    :manage_settings_projects,
    :manage_settings_merge_types,
    :manage_settings_pages,
    :manage_deploy_keys,
    :manage_webhooks,
    :set_social_preview,
    :edit_repo_announcement_banners,
    :edit_repo_protections,
    :edit_repo_custom_properties_values,
    :write_repository_actions_settings,
    :write_repository_actions_environments,
    :write_repository_actions_runners,
    :write_repository_actions_secrets,
    :write_repository_actions_variables,
  ]

  # These are the FGPs that grant access to bits of the repository settings page, but only if the repository is
  # a public repository. Used with REPOSITORY_SETTINGS_FGPS to decide if we should render the settings tab.
  PUBLIC_REPOSITORY_SETTINGS_FGPS = [:set_interaction_limits]

  # Public: Can a user access one or more repository settings options?
  #
  # actor - The User to check permissions for.
  #
  # Returns a Promise<Boolean>.
  def async_can_view_repository_settings?(actor)
    return Promise.resolve(false) unless actor.present?

    actions = if public?
      REPOSITORY_SETTINGS_FGPS + PUBLIC_REPOSITORY_SETTINGS_FGPS
    else
      REPOSITORY_SETTINGS_FGPS
    end

    async_authorized_via_policy?(actor, actions, { version: 2 })
  end

  def async_can_star?(actor)
    return Promise.resolve(false) unless actor.present?
    async_authorized_via_policy?(actor, :star_repo)
  end

  def show_config_authzd_enabled?
    return @show_config_authzd_enabled if defined?(@show_config_authzd_enabled)
    @show_config_authzd_enabled = owner&.custom_roles_supported?
  end

  def async_show_config_for?(actor)
    return false unless actor.present? # fail fast for logged out users
    return false unless show_config_authzd_enabled? # flipper - will trigger a db call
    return false if advisory_workspace? # association will trigger a db query
    async_can_view_repository_settings?(actor)
  end

  # Repository navigation optimizations
  # Batch several authzd permission under one request to reduce number of network calls in separated partials
  def batched_layout_authzd_permissions(actor, action)
    T.bind(self, ::Repository)

    @batched_layout_authzd_permissions ||= Hash.new do |hash, user|
      show_config, can_toggle_discussions_setting, can_manage_security_products = Promise.all([
        async_show_config_for?(user),
        async_can_toggle_discussions_setting?(user),
        SecurityProduct::Permissions::RepoAuthz.new(self, actor: user).async_can_manage_security_products?,
      ]).sync

      hash[user] = {
        show_config: show_config,
        can_toggle_discussions_setting: can_toggle_discussions_setting,
        can_manage_security_products: can_manage_security_products,
      }
    end

    @batched_layout_authzd_permissions[actor][action]
  end

  def async_subject_attributes
    Promise.all([
      async_owner,
      async_business,
      async_owning_organization_id,
      async_internal?,
      async_writable?,
    ]).then do |(owner, business, owning_organization_id, is_internal, is_writable)|
      {
        "repository.public"              => public?,
        "repository.owner.id"            => owner_id,
        "subject.id"                     => id,
        "subject.type"                   => "Repository",
        "subject.organization.id"        => owner&.organization? ? owner.id : nil,
        "subject.repository.id"          => id,
        "subject.repository.public"      => public?,
        "subject.repository.internal"    => is_internal,
        "subject.owner.id"               => owner_id,
        "subject.business.id"            => business&.id,
        "subject.repository.owner.id"    => owner_id,
        "subject.owning_organization.id" => owning_organization_id,
        "repository.owner.type"          => owner&.class&.name,
        "subject.repository.owner.type"  => owner&.class&.name,
        "subject.repository.writable"    => is_writable,
        "subject.repository.network_id"  => source_id,
      }
    end
  end

  private

  # Internal: Generic method to check if a user is authorized via an authzd policy
  def async_authorized_via_policy?(actor, action, context = {})
    Platform::Loaders::Permissions::BatchAuthorize.load(
      action: action,
      actor: actor,
      subject: self,
      context: context
    ).then do |result|
      result.allow?
    end
  end
end
