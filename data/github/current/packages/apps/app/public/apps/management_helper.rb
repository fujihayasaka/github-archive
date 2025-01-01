# typed: strict
# frozen_string_literal: true

# This module is a public interface callers outside this package can use to
# grant, revoke, enumerate and check App Management authorization.
module Apps
  module ManagementHelper
    include Team::Nested

    AppOwnerType = T.type_alias { T.any(Business, Organization, User) }

    # Replacement
    # from: Permissions::Enumerator.actor_ids_with_permission(action: :manage_all_apps, subject_id: org.id)
    #   to: Apps::ManagementHelper.user_ids_with_app_manager_role(on: org)
    sig { params(on: AppOwnerType).returns(T::Array[Integer]) }
    def self.user_ids_with_app_manager_role(on:)
      case on
      when Business
        return [] unless enterprise_app_manager_enabled?(on:)
        user_members = user_ids_with_app_manager_role_directly_granted(on:)
        business_teams = BusinessTeam.where(id: business_team_ids_with_app_manager_role(on:))
        business_team_members = business_teams.flat_map { |team| team.members.pluck(:id) }
        user_members + business_team_members
      when Organization
        user_members = user_ids_with_app_manager_role_directly_granted(on:)
        teams = Team.where(id: team_ids_with_app_manager_role(on:))
        team_members = member_ids_of(teams, immediate_only: false)
        # TODO: get business teams for orgs once enterprise team role assignments is enabled
        user_members + team_members
      when User
        []
      end
    end

    sig { params(on: AppOwnerType).returns(T::Array[Integer]) }
    def self.user_ids_with_app_manager_role_directly_granted(on:)
      case on
      when Business
        return [] unless enterprise_app_manager_enabled?(on:)
        UserRole
          .where(target_id: on.id, target_type: on.class.name)
          .where(role: Role.enterprise_app_manager_role, actor_type: "User")
          .pluck(:actor_id)
      when Organization
        UserRole
        .where(target_id: on.id, target_type: on.class.name)
        .where(role: Role.app_manager_role, actor_type: "User")
        .pluck(:actor_id)
      when User
        []
      end
    end

    sig { params(on: AppOwnerType).returns(T::Array[Integer]) }
    def self.team_ids_with_app_manager_role(on:)
      case on
      when Organization
        team_ids = UserRole
          .where(target_id: on.id, target_type: on.class.name)
          .where(role: Role.app_manager_role, actor_type: "Team")
          .pluck(:actor_id)

        teams = Team.where(id: team_ids)
        descendants = teams.flat_map { |team| team.descendants.pluck(:id) }

        team_ids.concat(descendants)
      else
        []
      end
    end


    sig { params(on: AppOwnerType).returns(T::Array[Integer]) }
    def self.business_team_ids_with_app_manager_role(on:)
      case on
      when Business
        # TODO: enable descendants once nested teams are functional for BusinessTeams
        return [] unless enterprise_app_manager_enabled?(on:)

        UserRole
        .where(target_id: on.id, target_type: on.class.name)
        .where(role: Role.enterprise_app_manager_role, actor_type: "BusinessTeam")
        .pluck(:actor_id)
      when Organization
        UserRole
          .where(target_id: on.id, target_type: on.class.name)
          .where(role: Role.app_manager_role, actor_type: "BusinessTeam")
          .pluck(:actor_id)
      when User
        []
      end
    end

    # Replacement
    # from: Permissions::Enumerator.actor_ids_with_permission(action: :grantable_manage_organization_apps, subject_id: org.id)
    #   to: Apps::ManagementHelper.user_ids_grantable_for_app_manager_role(on: org)
    #
    # User IDs of members that are not admin, nor already have been granted the role
    sig { params(on: AppOwnerType).returns(T::Array[Integer]) }
    def self.user_ids_grantable_for_app_manager_role(on:)
      case on
      when Business
        return [] unless enterprise_app_manager_enabled?(on:)
        all_members = on.all_member_ids
        admins = on.owners.pluck(:id)
        already_granted = user_ids_with_app_manager_role_directly_granted(on:)
        all_members - admins - already_granted
      when Organization
        all_members = on.member_ids
        admins = on.admin_ids
        already_granted = user_ids_with_app_manager_role_directly_granted(on:)
        all_members - admins - already_granted
      when User
        []
      end
    end

    # Replacement
    # from: Permissions::Enumerator.actor_ids_with_permission(action: :manage_app, subject_id: app.id)
    #   to: Apps::ManagementHelper.user_ids_with_app_owner_role(on: app)
    sig { params(on: Integration).returns(T::Array[Integer]) }
    def self.user_ids_with_app_owner_role(on:)
      case on.owner
      when Business
        user_members = user_ids_with_app_owner_role_directly_granted(on:)

        business_team_members = if on.owner.erp_feature_enabled?(:enterprise_teams_crud)
          business_teams = BusinessTeam.where(id: business_team_ids_with_app_owner_role(on:))
          business_teams.flat_map { |team| team.members.pluck(:id) }
        else
          []
        end

        (user_members + business_team_members).uniq
      when Organization
        user_members = user_ids_with_app_owner_role_directly_granted(on:)

        teams = Team.where(id: team_ids_with_app_owner_role(on:))
        team_members = member_ids_of(teams, immediate_only: false)

        business_teams = BusinessTeam.where(id: business_team_ids_with_app_owner_role(on:))
        business_team_members = business_teams.flat_map { |team| team.members.pluck(:id) }

        (user_members + team_members + business_team_members).uniq
      else
        []
      end
    end

    sig { params(on: Integration).returns(T::Array[Integer]) }
    def self.user_ids_with_app_owner_role_directly_granted(on:)
      return [] if on.owner.is_a?(User) && !on.owner.is_a?(Organization)

      UserRole
        .where(target: on)
        .where(role: Role.app_owner_role, actor_type: "User")
        .pluck(:actor_id)
    end

    sig { params(on: Integration).returns(T::Array[Integer]) }
    def self.team_ids_with_app_owner_role(on:)
      return [] if on.owner.is_a?(User) && !on.owner.is_a?(Organization)
      return [] unless on.owner.is_a?(Organization)
      return [] if on.owner.is_a?(Business)

      team_ids = UserRole
        .where(target_id: on.id, target_type: on.class.name)
        .where(role: Role.app_owner_role, actor_type: "Team")
        .pluck(:actor_id)

      teams = Team.where(id: team_ids)
      descendants = teams.flat_map { |team| team.descendants.pluck(:id) }

      (team_ids + descendants).uniq
    end

    sig { params(on: Integration).returns(T::Array[Integer]) }
    def self.business_team_ids_with_app_owner_role(on:)
      return [] if on.owner.is_a?(User) && !on.owner.is_a?(Organization)
      return [] if on.owner.is_a?(Business) && !on.owner.erp_feature_enabled?(:enterprise_teams_crud)

      UserRole
        .where(target_id: on.id, target_type: on.class.name)
        .where(role: Role.app_owner_role, actor_type: "BusinessTeam")
        .pluck(:actor_id)
    end

    # Replacement
    # from: Permissions::Enumerator.actor_ids_with_permission(action: :grantable_manage_app, subject_id: app.id, context: { owner_id: org.id })
    #   to: Apps::ManagementHelper.user_ids_grantable_for_app_owner_role(on: app)
    #
    # User IDs of members of the app owner that are not admin, nor app managers, nor already have been granted the role
    sig { params(on: Integration).returns(T::Array[Integer]) }
    def self.user_ids_grantable_for_app_owner_role(on:)
      app_owner = on.owner

      case app_owner
      when Business
        all_members = app_owner.all_member_ids
        admins = app_owner.owners.pluck(:id)
        app_managers = user_ids_with_app_manager_role_directly_granted(on: app_owner)
        already_app_owners = user_ids_with_app_owner_role_directly_granted(on:)

        all_members - admins - app_managers - already_app_owners
      when Organization
        all_members = app_owner.member_ids
        admins = app_owner.admin_ids
        app_managers = user_ids_with_app_manager_role_directly_granted(on: app_owner)
        already_app_owners = user_ids_with_app_owner_role_directly_granted(on:)

        all_members - admins - app_managers - already_app_owners
      else
        []
      end
    end

    sig { params(on: Integration).returns(T::Array[Integer]) }
    def self.team_ids_grantable_for_app_owner_role(on:)
      app_owner = on.owner
      return [] if app_owner.is_a?(User) && !app_owner.is_a?(Organization)
      return [] if app_owner.is_a?(Business)

      all_teams = app_owner.teams.pluck(:id)
      app_manager_teams = team_ids_with_app_manager_role(on: app_owner)
      already_app_owners = team_ids_with_app_owner_role(on:)
      all_teams - app_manager_teams - already_app_owners
    end

    sig { params(on: Integration).returns(T::Array[Integer]) }
    def self.business_team_ids_grantable_for_app_owner_role(on:)
      owner = on.owner

      case owner
      when Business
        return [] unless owner.erp_feature_enabled?(:enterprise_teams_crud)
        all_biz_teams = owner.business_teams.pluck(:id)
        biz_teams_with_owner_role = business_team_ids_with_app_owner_role(on:)
        biz_teams_with_app_manager_role = business_team_ids_with_app_manager_role(on: owner)
        all_biz_teams - biz_teams_with_owner_role - biz_teams_with_app_manager_role
      when Organization
        all_biz_teams = Orgs::Domain::Teams.new.business_team_ids_for_assigned_orgs(organization_id: owner.id)
        biz_teams_with_owner_role = business_team_ids_with_app_owner_role(on:)
        biz_teams_with_app_manager_role = business_team_ids_with_app_manager_role(on: owner)
        all_biz_teams - biz_teams_with_owner_role - biz_teams_with_app_manager_role
      else
        []
      end
    end

    # Replacement
    # from: Permissions::Enumerator.subject_ids_for_permission(action: :manage_app, actor_id: actor.id)
    #   to: Apps::ManagementHelper.app_ids_directly_managed_by(actor)
    # `on` parameter added for feature flag check only
    sig { params(actor: User, on: T.nilable(AppOwnerType)).returns(T::Array[Integer]) }
    def self.app_ids_directly_managed_by(actor:, on: nil)
      return [] if on.is_a?(User) && !on.is_a?(Organization)

      if !on.nil?
        directly_granted = UserRole
          .where(actor_id: actor.id, actor_type: actor.class.name)
          .where(role: Role.app_owner_role, target_type: "Integration")
          .pluck(:target_id)

        if (on.is_a?(Organization)) || (on.is_a?(Business) && on.erp_feature_enabled?(:enterprise_teams_crud))
          granted_via_team_or_business_team = app_ids_managed_by_user_via_team_or_business_team_membership(actor:)
          directly_granted + granted_via_team_or_business_team
        else
          granted_via_team = app_ids_managed_by_user_via_team_membership(actor)
          directly_granted + granted_via_team
        end
      else
        UserRole
          .where(actor_id: actor.id, actor_type: actor.class.name)
          .where(role: Role.app_owner_role, target_type: "Integration")
          .pluck(:target_id)
      end
    end

    sig { params(actor: User).returns(T::Array[Integer]) }
    def self.app_ids_managed_by_user_via_team_membership(actor)
      user_teams = actor.teams.all
      user_teams_and_ancestor_teams = user_teams.flat_map { |team| team.id_and_ancestor_ids }.uniq

      UserRole
        .where(actor_id: user_teams_and_ancestor_teams, actor_type: "Team")
        .where(role: Role.app_owner_role, target_type: "Integration")
        .pluck(:target_id)
    end

    sig { params(actor: User).returns(T::Array[Integer]) }
    def self.app_ids_managed_by_user_via_team_or_business_team_membership(actor:)
      team_ids = Orgs::Domain::Teams.new.team_ids_by_actor_id_for(actor_type: "User", actor_ids: [actor.id])[actor.id] || []
      teams = Team.where(id: team_ids) + BusinessTeam.where(id: team_ids)
      user_teams_and_ancestor_team_ids = teams.flat_map { |team| team.id_and_ancestor_ids }.uniq

      UserRole
        .where(actor_id: user_teams_and_ancestor_team_ids, actor_type: %w(Team BusinessTeam))
        .where(role: Role.app_owner_role, target_type: "Integration")
        .pluck(:target_id)
    end

    sig { params(on: AppOwnerType, actor: User).returns(T::Boolean) }
    def self.manages_all_apps?(on:, actor:)
      async_manages_all_apps?(on:, actor:).sync
    end

    sig { params(app: Integration, actor: User).returns(T::Boolean) }
    def self.manages_app?(app:, actor:)
      ::Permissions::Enforcer.authorize(
        actor: actor,
        action: :manage_app,
        subject: app,
      ).allow?
    end

    sig { params(on: AppOwnerType, actor: User).returns(Promise[T::Boolean]) }
    def self.async_manages_all_apps?(on:, actor:)
      Platform::Loaders::Permissions::BatchAuthorize.load(
        actor: actor,
        action: :manage_all_apps,
        subject: on
      ).then(&:allow?)
    end

    sig { params(on: AppOwnerType, actor: User).returns(T::Boolean) }
    def self.can_create_apps?(on:, actor:)
      fgp = on.is_a?(Business) ? :create_enterprise_integrations : :create_org_integrations
      async_has_app_management_fgp?(fgp, on:, actor:).sync
    end

    sig { params(on: AppOwnerType, actor: User).returns(T::Boolean) }
    def self.can_update_all_apps?(on:, actor:)
      fgp = on.is_a?(Business) ? :edit_enterprise_integrations : :edit_org_integrations
      async_has_app_management_fgp?(fgp, on:, actor:).sync
    end

    sig { params(on: AppOwnerType, actor: User).returns(T::Boolean) }
    def self.can_delete_all_apps?(on:, actor:)
      fgp = on.is_a?(Business) ? :delete_enterprise_integrations : :delete_org_integrations
      async_has_app_management_fgp?(fgp, on:, actor:).sync
    end

    sig { params(on: AppOwnerType, actor: User).returns(T::Boolean) }
    def self.can_view_all_apps?(on:, actor:)
      fgp = on.is_a?(Business) ? :view_enterprise_integrations : :view_org_integrations
      async_has_app_management_fgp?(fgp, on:, actor:).sync
    end

    sig { params(action: Symbol, on: AppOwnerType, actor: User).returns(Promise[T::Boolean]) }
    def self.async_has_app_management_fgp?(action, on:, actor:)
      Platform::Loaders::Permissions::BatchAuthorize
        .load(actor:, action:, subject: on)
        .then(&:allow?)
    end

    sig { params(app: Integration, actor: User).returns(T::Boolean) }
    def self.can_view?(app:, actor:)
      async_has_app_owner_fgp?(:view_integration, app:, actor:).sync
    end

    sig { params(app: Integration, actor: User).returns(T::Boolean) }
    def self.can_edit?(app:, actor:)
      async_has_app_owner_fgp?(:edit_integration, app:, actor:).sync
    end

    sig { params(app: Integration, actor: User).returns(T::Boolean) }
    def self.can_delete?(app:, actor:)
      async_has_app_owner_fgp?(:delete_integration, app:, actor:).sync
    end

    sig { params(action: Symbol, app: Integration, actor: User).returns(Promise[T::Boolean]) }
    def self.async_has_app_owner_fgp?(action, app:, actor:)
      return Promise.resolve(T.let(true, T::Boolean)) if app.owner.is_a?(Business) && app.owner.owner?(actor)

      Platform::Loaders::Permissions::BatchAuthorize
        .load(actor:, action:, subject: app, context: { "subject.owner.type": app.owner.class.name, version: 2 })
        .then(&:allow?)
    end

    sig { params(app: Integration).returns(::Permissions::Granters::RoleGrantResult) }
    def self.revoke_app_owners(app:)
      UserRole
        .where(target: app, role: Role.app_owner_role)
        .includes(:actor)
        .each do |user_role|
          ::Permissions::Granters::RoleGranter.new(
            actor: user_role.actor,
            target: app,
            role: Role.app_owner_role,
          ).revoke_if_exists!
        end

      ::Permissions::Granters::RoleGrantResult.success!
    rescue ::Permissions::Granters::RoleGranter::GrantFailure => err
      ::Permissions::Granters::RoleGrantResult.failure!(reason: err.message)
    end

    sig { params(on: T.nilable(AppOwnerType), actor: T.nilable(User)).returns(T::Boolean) }
    def self.can_view_any_app?(on:, actor:)
      return false if on.nil? || actor.nil?
      if on.is_a?(Business)
        Platform::Loaders::Permissions::BatchAuthorize
          .load(actor:, action: :view_any_enterprise_integration, subject: on)
          .then(&:allow?)
          .sync
      elsif on.is_a?(Organization)
        Platform::Loaders::Permissions::BatchAuthorize
          .load(actor:, action: :view_any_org_integration, subject: on)
          .then(&:allow?)
          .sync
      else
        false
      end
    end

    sig { params(on: AppOwnerType).returns(T::Boolean) }
    def self.enterprise_app_manager_enabled?(on:)
      on.feature_flag_enabled_or_raise?(:enterprise_app_manager) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
    end
  end
end
