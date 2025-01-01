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
      return [] if on.is_a?(Business) && !on.feature_enabled?(:enterprise_app_management_via_fgps)

      if teams_enabled_for_apps_management?(on:)
        user_members = user_ids_with_app_manager_role_directly_granted(on:)
        teams = Team.where(id: team_ids_with_app_manager_role(on:))
        team_members = member_ids_of(teams, immediate_only: false)

        (user_members + team_members).uniq
      else
        role = on.is_a?(Business) ? Role.enterprise_app_manager_role : Role.app_manager_role

        UserRole
          .where(target_id: on.id, target_type: on.class.name)
          .where(role: role, actor_type: "User")
          .pluck(:actor_id)
      end
    end

    sig { params(on: AppOwnerType).returns(T::Array[Integer]) }
    def self.user_ids_with_app_manager_role_directly_granted(on:)
      return [] if on.is_a?(Business) && !on.feature_enabled?(:enterprise_app_management_via_fgps)

      role = on.is_a?(Business) ? Role.enterprise_app_manager_role : Role.app_manager_role

      UserRole
        .where(target_id: on.id, target_type: on.class.name)
        .where(role: role, actor_type: "User")
        .pluck(:actor_id)
    end


    sig { params(on: AppOwnerType).returns(T::Array[Integer]) }
    def self.team_ids_with_app_manager_role(on:)
      return [] unless teams_enabled_for_apps_management?(on:)
      return [] if on.is_a?(Business) && !on.feature_enabled?(:enterprise_app_management_via_fgps)

      role = on.is_a?(Business) ? Role.enterprise_app_manager_role : Role.app_manager_role

      team_ids = UserRole
        .where(target_id: on.id, target_type: on.class.name)
        .where(role: role, actor_type: "Team")
        .pluck(:actor_id)

      teams = Team.where(id: team_ids)
      descendants = teams.flat_map { |team| team.descendants.pluck(:id) }

      team_ids.concat(descendants)
    end

    sig { params(on: AppOwnerType).returns(T::Array[Integer]) }
    def self.business_team_ids_with_app_manager_role(on:)
      return [] unless teams_enabled_for_apps_management?(on:)
      return [] unless business_teams_enabled_for_apps_management?(on:)

      role = on.is_a?(Business) ? Role.enterprise_app_manager_role : Role.app_manager_role

      team_ids = UserRole
        .where(target_id: on.id, target_type: on.class.name)
        .where(role: role, actor_type: "BusinessTeam")
        .pluck(:actor_id)

      team_ids.uniq
    end

    # Replacement
    # from: Permissions::Enumerator.actor_ids_with_permission(action: :grantable_manage_organization_apps, subject_id: org.id)
    #   to: Apps::ManagementHelper.user_ids_grantable_for_app_manager_role(on: org)
    #
    # User IDs of members that are not admin, nor already have been granted the role
    sig { params(on: AppOwnerType).returns(T::Array[Integer]) }
    def self.user_ids_grantable_for_app_manager_role(on:)
      return [] if on.is_a?(Business) && !on.feature_enabled?(:enterprise_app_management_via_fgps)

      case on
      when Business
        on.user_accounts.pluck(:user_id) - user_ids_with_app_manager_role(on:) - on.admins.pluck(:id)
      when Organization
        all_members = on.member_ids
        admins = on.admin_ids
        already_granted = user_ids_with_app_manager_role_directly_granted(on:)

        all_members - admins - already_granted
      when User
        []
      else
        T.absurd(on)
      end
    end

    sig { params(on: AppOwnerType).returns(T::Array[Integer]) }
    def self.team_ids_grantable_for_app_manager_role(on:)
      return [] unless on.feature_enabled?(:enable_teams_to_manage_apps)

      case on
      when Business
        return [] unless on.feature_enabled?(:enterprise_app_management_via_fgps)
        all_biz_teams = Orgs::Domain::Teams.new.business_team_ids_for_assigned_orgs(organization_id: on.id)
        all_biz_teams - team_ids_with_app_manager_role(on:)
      when Organization
        on.teams.pluck(:id) - team_ids_with_app_manager_role(on:)
      when User
        []
      else
        T.absurd(on)
      end
    end

    sig { params(on: Integration).returns(T::Array[Integer]) }
    def self.business_team_ids_grantable_for_app_owner_role(on:)
      owner = on.owner

      return [] unless owner.is_a?(Organization)
      return [] unless teams_enabled_for_apps_management?(on: owner)
      return [] unless business_teams_enabled_for_apps_management?(on: owner)

      all_biz_teams = Orgs::Domain::Teams.new.business_team_ids_for_assigned_orgs(organization_id: owner.id)
      biz_teams_with_owner_role = business_team_ids_with_app_owner_role(on:)
      biz_teams_with_app_manager_role = business_team_ids_with_app_manager_role(on: owner)

      all_biz_teams - biz_teams_with_owner_role - biz_teams_with_app_manager_role
    end

    # Replacement
    # from: Permissions::Enumerator.actor_ids_with_permission(action: :manage_app, subject_id: app.id)
    #   to: Apps::ManagementHelper.user_ids_with_app_owner_role(on: app)
    sig { params(on: Integration).returns(T::Array[Integer]) }
    def self.user_ids_with_app_owner_role(on:)
      return [] if on.owner.is_a?(Business) && !business_teams_enabled_for_apps_management?(on: on.owner)

      if teams_enabled_for_apps_management?(on: on.owner)
        user_members = user_ids_with_app_owner_role_directly_granted(on:)
        teams = Team.where(id: team_ids_with_app_owner_role(on:))
        team_members = member_ids_of(teams, immediate_only: false)

        business_teams = BusinessTeam.where(id: business_team_ids_with_app_owner_role(on:))
        business_team_members = business_teams.flat_map { |team| team.members.pluck(:id) }

        (user_members + team_members + business_team_members).uniq
      else
        UserRole
          .where(target: on)
          .where(role: Role.app_owner_role, actor_type: "User")
          .pluck(:actor_id)
      end
    end

    sig { params(on: Integration).returns(T::Array[Integer]) }
    def self.user_ids_with_app_owner_role_directly_granted(on:)
      return [] if on.owner.is_a?(Business) && !on.owner.feature_enabled?(:enterprise_app_management_via_fgps)

      UserRole
        .where(target: on)
        .where(role: Role.app_owner_role, actor_type: "User")
        .pluck(:actor_id)
    end

    sig { params(on: Integration).returns(T::Array[Integer]) }
    def self.team_ids_with_app_owner_role(on:)
      return [] unless on.owner.is_a?(Organization) && teams_enabled_for_apps_management?(on: on.owner)

      team_ids = UserRole
        .where(target_id: on.id, target_type: on.class.name)
        .where(role: Role.app_owner_role, actor_type: "Team")
        .pluck(:actor_id)

      teams = Team.where(id: team_ids)
      descendants = teams.flat_map { |team| team.descendants.pluck(:id) }

      team_ids = (team_ids + descendants).uniq
    end

    sig { params(on: Integration).returns(T::Array[Integer]) }
    def self.business_team_ids_with_app_owner_role(on:)
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

      return [] unless app_owner.is_a?(Organization) && teams_enabled_for_apps_management?(on: app_owner)

      all_teams = app_owner.teams.pluck(:id)
      app_manager_teams = team_ids_with_app_manager_role(on: app_owner)
      already_app_owners = team_ids_with_app_owner_role(on:)
      all_teams - app_manager_teams - already_app_owners
    end

    # Replacement
    # from: Permissions::Enumerator.subject_ids_for_permission(action: :manage_app, actor_id: actor.id)
    #   to: Apps::ManagementHelper.app_ids_directly_managed_by(actor)
    sig { params(actor: User, on: T.nilable(Organization)).returns(T::Array[Integer]) }
    def self.app_ids_directly_managed_by(actor:, on: nil)
      if !on.nil? && teams_enabled_for_apps_management?(on:)
        directly_granted = UserRole
          .where(actor_id: actor.id, actor_type: actor.class.name)
          .where(role: Role.app_owner_role, target_type: "Integration")
          .pluck(:target_id)

        granted_via_team = app_ids_managed_by_user_via_team_membership(actor)
        granted_via_enterprise_team = app_ids_managed_by_user_via_enterprise_team_membership(actor:, on:)

        if business_teams_enabled_for_apps_management?(on:)
          directly_granted + granted_via_team + granted_via_enterprise_team
        else
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

    sig { params(actor: User, on: AppOwnerType).returns(T::Array[Integer]) }
    def self.app_ids_managed_by_user_via_enterprise_team_membership(actor:, on:)
      business_id = on.present? && on.is_a?(Organization) && on.business.present? ? on.business&.id : nil
      return [] if business_id.nil?
      team_ids = Orgs::Domain::Teams.new.business_team_ids_for(business_id: business_id, user_id: actor.id)

      UserRole
        .where(actor_id: team_ids, actor_type: "BusinessTeam")
        .where(role: Role.app_owner_role, target_type: "Integration")
        .pluck(:target_id)
    end

    sig { params(on: AppOwnerType, actor: User).returns(T::Boolean) }
    def self.manages_all_apps?(on:, actor:)
      async_manages_all_apps?(on:, actor:).sync
    end

    sig { params(app: Integration, actor: User).returns(T::Boolean) }
    def self.manages_app?(app:, actor:)
      owner = app.owner
      return false if owner.is_a?(Business) && !owner.owner?(actor) && !owner.feature_enabled?(:enterprise_app_management_via_fgps)

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
      return  Promise.resolve(T.let(false, T::Boolean)) if on.is_a?(Business) && !on.adminable_by?(actor) && !on.feature_enabled?(:enterprise_app_management_via_fgps)
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
      if app.owner.is_a?(Business) && !app.owner.feature_enabled?(:enterprise_app_management_via_fgps)
        if app.owner.owner?(actor)
          return Promise.resolve(T.let(true, T::Boolean))
        else
          return Promise.resolve(T.let(false, T::Boolean))
        end
      end

      feature_enabled = business_teams_enabled_for_apps_management?(on: app.owner) || teams_enabled_for_apps_management?(on: app.owner)
      version = feature_enabled ? 2 : 1
      Platform::Loaders::Permissions::BatchAuthorize
        .load(actor:, action:, subject: app, context: { "subject.owner.type": app.owner.class.name, version: version })
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

    sig { params(on: AppOwnerType, actor: User).returns(T::Boolean) }
    def self.can_view_any_app?(on:, actor:)
      Platform::Loaders::Permissions::BatchAuthorize
        .load(actor:, action: :view_any_org_integration, subject: on)
        .then(&:allow?)
        .sync
    end

    sig { params(on: AppOwnerType).returns(T::Boolean) }
    def self.business_teams_enabled_for_apps_management?(on:)
      if on.is_a?(Organization)
        return false unless teams_enabled_for_apps_management?(on:)
        return true if on.feature_enabled?(:enterprise_app_management_via_fgps) && on.feature_enabled?(:enterprise_teams_org_membership_macro) && on.feature_enabled?(:enable_teams_to_manage_apps)
        return true if on.billable_owner.present? &&
          on.billable_owner.is_a?(Business) &&
          on.billable_owner.feature_enabled?(:enterprise_app_management_via_fgps) &&
          on.billable_owner.feature_enabled?(:enterprise_teams_org_membership_macro) &&
          on.billable_owner.feature_enabled?(:enable_teams_to_manage_apps)
        false
      elsif on.is_a?(Business)
        on.feature_enabled?(:enterprise_app_management_via_fgps) && on.feature_enabled?(:enterprise_teams_org_membership_macro) && on.feature_enabled?(:enable_teams_to_manage_apps)
      else
        false
      end
    end

    sig { params(on: AppOwnerType).returns(T::Boolean) }
    def self.teams_enabled_for_apps_management?(on:)
      if on.is_a?(Organization)
        return true if on.feature_enabled?(:enable_teams_to_manage_apps)
        return true if on.billable_owner.present? && on.billable_owner.is_a?(Business) && on.billable_owner.feature_enabled?(:enable_teams_to_manage_apps)
        false
      elsif on.is_a?(Business)
        on.feature_enabled?(:enable_teams_to_manage_apps)
      else
        false
      end
    end
  end
end
