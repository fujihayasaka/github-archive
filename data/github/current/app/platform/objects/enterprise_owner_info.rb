# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class EnterpriseOwnerInfo < Platform::Objects::Base
      description "Enterprise information visible to enterprise owners or enterprise owners' personal access tokens (classic) with read:enterprise or admin:enterprise scope."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, business)
        true if permission.access_allowed?(:view_enterprise_identity_provider, resource: business, repo: nil, organization: nil, allow_integrations: false, allow_user_via_granular_actor: false, raise_on_error: false)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        object.owner?(permission.viewer) || permission.viewer&.site_admin?
      end

      minimum_accepted_scopes ["read:enterprise"]

      # MEMBERS FIELDS

      field :admins, resolver: Resolvers::EnterpriseAdmins, description: "A list of all of the administrators for this enterprise.", connection: true, exempt_from_spam_filter_check: true
      field :pending_admin_invitations, resolver: Resolvers::EnterpriseAdministratorInvitations, description: "A list of pending administrator invitations for the enterprise.", connection: true
      field :pending_unaffiliated_member_invitations, resolver: Resolvers::EnterpriseMemberInvitations, description: "A list of pending unaffiliated member invitations for the enterprise.", connection: true,
        visibility: { public: { environments: [:dotcom] } }
      field :pending_member_invitations, resolver: Resolvers::EnterprisePendingMemberInvitations, description: "A list of pending member invitations for organizations in the enterprise.", connection: true
      field :failed_invitations, resolver: Resolvers::EnterpriseFailedInvitations, description: "A list of failed invitations in the enterprise.", connection: true
      field :outside_collaborators, resolver: Resolvers::EnterpriseOutsideCollaborators, description: "A list of outside collaborators across the repositories in the enterprise.", connection: true
      field :support_entitlements, resolver: Resolvers::EnterpriseSupportEntitlements,
        description: "A list of members with a support entitlement.",
        connection: true,
        visibility: { public: { environments: [:dotcom] }, internal: { environments: [:enterprise] } }

      field :pending_collaborator_invitations,
        resolver: Resolvers::EnterprisePendingCollaboratorInvitations,
        description: "A list of pending collaborator invitations across the repositories in the enterprise.",
        connection: true

      field :organization_invitations, Connections.define(Objects::EnterpriseOrganizationInvitation), description: "A list of invitations for organizations to join this enterprise.", null: true, connection: true do
        visibility :under_development
        argument :status, Enums::EnterpriseOrganizationInvitationStatus, description: "If supplied, only returns invitations in that state.", required: false
        argument :order_by, Inputs::EnterpriseOrganizationInvitationOrder, description: "Ordering options for EnterpriseOrganizationInvitations returned from the connection.", required: false, default_value: { field: "created_at", direction: "ASC" }
      end

      def organization_invitations(args = {})
        business_full_plan_required!(@object)

        invites = @object.organization_invitations
        invites = invites.with_status(args[:status]) if args[:status]

        if args[:order_by]
          field = args[:order_by][:field]
          direction = args[:order_by][:direction]
          invites = invites.reorder("business_organization_invitations.#{field} #{direction}")
        end

        invites
      end

      # Business settings fields:

      field :default_repository_permission_setting, Enums::EnterpriseDefaultRepositoryPermissionSettingValue,
        description: "The setting value for base repository permissions for organizations in this enterprise.", null: false

      def default_repository_permission_setting
        ensure_business_can_use_api!(@object)
        business_full_plan_required!(@object)

        if !@object.default_repository_permission_policy?
          return T.must(Enums::EnterpriseDefaultRepositoryPermissionSettingValue.values["NO_POLICY"]).value
        end

        case @object.default_repository_permission
        when :admin
          T.must(Enums::EnterpriseDefaultRepositoryPermissionSettingValue.values["ADMIN"]).value
        when :write
          T.must(Enums::EnterpriseDefaultRepositoryPermissionSettingValue.values["WRITE"]).value
        when :read
          T.must(Enums::EnterpriseDefaultRepositoryPermissionSettingValue.values["READ"]).value
        when :none
          T.must(Enums::EnterpriseDefaultRepositoryPermissionSettingValue.values["NONE"]).value
        end
      end

      field :default_repository_permission_setting_organizations, Connections.define(Objects::Organization), description: "A list of enterprise organizations configured with the provided base repository permission.", connection: true, null: false do
        argument :value, Enums::DefaultRepositoryPermissionField, "The permission to find organizations for.", required: true
        argument :order_by, Inputs::OrganizationOrder,
                 "Ordering options for organizations with this setting.",
                 required: false, default_value: { field: "login", direction: "ASC" }
      end

      def default_repository_permission_setting_organizations(value:, order_by:)
        ensure_business_can_use_api!(@object)
        business_full_plan_required!(@object)

        object.default_repository_permission_setting_organizations \
          value: value,
          order_by_field: order_by&.dig(:field),
          order_by_direction: order_by&.dig(:direction)
      end

      field :is_updating_default_repository_permission, Boolean, method: :updating_default_repository_permission?,
        description: "Whether or not the base repository permission is currently being updated.", null: false

      field :team_discussions_setting, Enums::EnterpriseEnabledDisabledSettingValue, description: "The setting value for whether team discussions are enabled for organizations in this enterprise.", null: false

      def team_discussions_setting
        ensure_business_can_use_api!(@object)
        business_full_plan_required!(@object)

        if !@object.team_discussions_policy?
          T.must(Enums::EnterpriseEnabledDisabledSettingValue.values["NO_POLICY"]).value
        elsif @object.team_discussions_allowed?
          T.must(Enums::EnterpriseEnabledDisabledSettingValue.values["ENABLED"]).value
        else
          T.must(Enums::EnterpriseEnabledDisabledSettingValue.values["DISABLED"]).value
        end
      end

      field :team_discussions_setting_organizations, Connections.define(Objects::Organization), description: "A list of enterprise organizations configured with the provided team discussions setting value.", connection: true, null: false do
        argument :value, Boolean, "The setting value to find organizations for.", required: true
        argument :order_by, Inputs::OrganizationOrder,
                 "Ordering options for organizations with this setting.",
                 required: false, default_value: { field: "login", direction: "ASC" }
      end

      def team_discussions_setting_organizations(value:, order_by:)
        ensure_business_can_use_api!(@object)
        business_full_plan_required!(@object)

        object.team_discussions_setting_organizations \
          value: value,
          order_by_field: order_by&.dig(:field),
          order_by_direction: order_by&.dig(:direction)
      end

      field :organization_projects_setting, Enums::EnterpriseEnabledDisabledSettingValue, description: "The setting value for whether organization projects are enabled for organizations in this enterprise.", null: false

      def organization_projects_setting
        ensure_business_can_use_api!(@object)
        business_full_plan_required!(@object)

        if !@object.organization_projects_policy?
          T.must(Enums::EnterpriseEnabledDisabledSettingValue.values["NO_POLICY"]).value
        elsif @object.organization_projects_enabled?
          T.must(Enums::EnterpriseEnabledDisabledSettingValue.values["ENABLED"]).value
        else
          T.must(Enums::EnterpriseEnabledDisabledSettingValue.values["DISABLED"]).value
        end
      end

      field :organization_projects_setting_organizations, Connections.define(Objects::Organization), description: "A list of enterprise organizations configured with the provided organization projects setting value.", connection: true, null: false do
        argument :value, Boolean, "The setting value to find organizations for.", required: true
        argument :order_by, Inputs::OrganizationOrder,
                 "Ordering options for organizations with this setting.",
                 required: false, default_value: { field: "login", direction: "ASC" }
      end

      def organization_projects_setting_organizations(value:, order_by:)
        ensure_business_can_use_api!(@object)
        business_full_plan_required!(@object)

        object.organization_projects_setting_organizations \
          value: value,
          order_by_field: order_by&.dig(:field),
          order_by_direction: order_by&.dig(:direction)
      end

      field :repository_projects_setting, Enums::EnterpriseEnabledDisabledSettingValue, description: "The setting value for whether repository projects are enabled in this enterprise.", null: false

      def repository_projects_setting
        ensure_business_can_use_api!(@object)
        business_full_plan_required!(@object)

        if !@object.repository_projects_policy?
          T.must(Enums::EnterpriseEnabledDisabledSettingValue.values["NO_POLICY"]).value
        elsif @object.repository_projects_enabled?
          T.must(Enums::EnterpriseEnabledDisabledSettingValue.values["ENABLED"]).value
        else
          T.must(Enums::EnterpriseEnabledDisabledSettingValue.values["DISABLED"]).value
        end
      end

      field :repository_projects_setting_organizations, Connections.define(Objects::Organization), description: "A list of enterprise organizations configured with the provided repository projects setting value.", connection: true, null: false do
        argument :value, Boolean, "The setting value to find organizations for.", required: true
        argument :order_by, Inputs::OrganizationOrder,
                 "Ordering options for organizations with this setting.",
                 required: false, default_value: { field: "login", direction: "ASC" }
      end

      def repository_projects_setting_organizations(value:, order_by:)
        ensure_business_can_use_api!(@object)
        business_full_plan_required!(@object)

        object.repository_projects_setting_organizations \
          value: value,
          order_by_field: order_by&.dig(:field),
          order_by_direction: order_by&.dig(:direction)
      end

      field :members_can_change_repository_visibility_setting, Enums::EnterpriseEnabledDisabledSettingValue, description: "The setting value for whether organization members with admin permissions on a repository can change repository visibility.", null: false

      def members_can_change_repository_visibility_setting
        ensure_business_can_use_api!(@object)
        business_full_plan_required!(@object)

        if !@object.members_can_change_repo_visibility_policy?
          T.must(Enums::EnterpriseEnabledDisabledSettingValue.values["NO_POLICY"]).value
        elsif @object.members_can_change_repo_visibility?
          T.must(Enums::EnterpriseEnabledDisabledSettingValue.values["ENABLED"]).value
        else
          T.must(Enums::EnterpriseEnabledDisabledSettingValue.values["DISABLED"]).value
        end
      end

      field :members_can_change_repository_visibility_setting_organizations, Connections.define(Objects::Organization), description: "A list of enterprise organizations configured with the provided can change repository visibility setting value.", connection: true, null: false do
        argument :value, Boolean, "The setting value to find organizations for.", required: true
        argument :order_by, Inputs::OrganizationOrder,
                 "Ordering options for organizations with this setting.",
                 required: false, default_value: { field: "login", direction: "ASC" }
      end

      def members_can_change_repository_visibility_setting_organizations(value:, order_by:)
        ensure_business_can_use_api!(@object)
        business_full_plan_required!(@object)

        object.members_can_change_repository_visibility_setting_organizations \
          value: value,
          order_by_field: order_by&.dig(:field),
          order_by_direction: order_by&.dig(:direction)
      end

      field :members_can_invite_collaborators_setting, Enums::EnterpriseEnabledDisabledSettingValue, description: "The setting value for whether members of organizations in the enterprise can invite outside collaborators.", null: false

      def members_can_invite_collaborators_setting
        ensure_business_can_use_api!(@object)
        business_full_plan_required!(@object)

        if !@object.members_can_invite_outside_collaborators_policy?
          T.must(Enums::EnterpriseEnabledDisabledSettingValue.values["NO_POLICY"]).value
        elsif @object.members_can_invite_outside_collaborators?
          T.must(Enums::EnterpriseEnabledDisabledSettingValue.values["ENABLED"]).value
        else
          T.must(Enums::EnterpriseEnabledDisabledSettingValue.values["DISABLED"]).value
        end
      end

      field :members_can_invite_collaborators_setting_organizations, Connections.define(Objects::Organization), description: "A list of enterprise organizations configured with the provided members can invite collaborators setting value.", connection: true, null: false do
        argument :value, Boolean, "The setting value to find organizations for.", required: true
        argument :order_by, Inputs::OrganizationOrder,
                 "Ordering options for organizations with this setting.",
                 required: false, default_value: { field: "login", direction: "ASC" }
      end

      def members_can_invite_collaborators_setting_organizations(value:, order_by:)
        ensure_business_can_use_api!(@object)
        business_full_plan_required!(@object)

        object.members_can_invite_collaborators_setting_organizations \
          value: value,
          order_by_field: order_by&.dig(:field),
          order_by_direction: order_by&.dig(:direction)
      end

      field :members_can_create_repositories_setting, Enums::EnterpriseMembersCanCreateRepositoriesSettingValue,
        description: "The setting value for whether members of organizations in the enterprise can create repositories.", null: true

      def members_can_create_repositories_setting
        ensure_business_can_use_api!(@object)
        business_full_plan_required!(@object)

        unless @object.members_can_create_repositories_policy?
          return T.must(Enums::EnterpriseMembersCanCreateRepositoriesSettingValue.values["NO_POLICY"]).value
        end

        # Backward-compatible values, wherein the state of internal repos is ignored.
        if @object.members_can_create_public_repositories? && @object.members_can_create_private_repositories?
          T.must(Enums::EnterpriseMembersCanCreateRepositoriesSettingValue.values["ALL"]).value
        elsif @object.members_can_create_public_repositories? && !@object.members_can_create_private_repositories?
          T.must(Enums::EnterpriseMembersCanCreateRepositoriesSettingValue.values["PUBLIC"]).value
        elsif !@object.members_can_create_public_repositories? && @object.members_can_create_private_repositories?
          T.must(Enums::EnterpriseMembersCanCreateRepositoriesSettingValue.values["PRIVATE"]).value
        else
          T.must(Enums::EnterpriseMembersCanCreateRepositoriesSettingValue.values["DISABLED"]).value
        end
      end

      field :members_can_create_public_repositories_setting, Boolean,
        description: "The setting value for whether members of organizations in the enterprise can create public repositories.", null: true

      def members_can_create_public_repositories_setting
        ensure_business_can_use_api!(@object)
        business_full_plan_required!(@object)

        return nil unless @object.members_can_create_repositories_policy?
        @object.members_can_create_public_repositories?
      end

      field :members_can_create_private_repositories_setting, Boolean,
        description: "The setting value for whether members of organizations in the enterprise can create private repositories.", null: true

      def members_can_create_private_repositories_setting
        ensure_business_can_use_api!(@object)
        business_full_plan_required!(@object)

        return nil unless @object.members_can_create_repositories_policy?
        @object.members_can_create_private_repositories?
      end

      field :members_can_create_internal_repositories_setting, Boolean,
        description: "The setting value for whether members of organizations in the enterprise can create internal repositories.", null: true

      def members_can_create_internal_repositories_setting
        ensure_business_can_use_api!(@object)
        business_full_plan_required!(@object)

        return nil unless @object.members_can_create_repositories_policy?
        @object.members_can_create_internal_repositories?
      end

      field :members_can_create_repositories_setting_organizations, Connections.define(Objects::Organization), description: "A list of enterprise organizations configured with the provided repository creation setting value.", connection: true, null: false do
        argument :value, Enums::OrganizationMembersCanCreateRepositoriesSettingValue, "The setting to find organizations for.", required: true
        argument :order_by, Inputs::OrganizationOrder,
                 "Ordering options for organizations with this setting.",
                 required: false, default_value: { field: "login", direction: "ASC" }
      end

      def members_can_create_repositories_setting_organizations(value:, order_by:)
        ensure_business_can_use_api!(@object)
        business_full_plan_required!(@object)

        object.members_can_create_repositories_setting_organizations \
          value: value,
          order_by_field: order_by&.dig(:field),
          order_by_direction: order_by&.dig(:direction)
      end

      field :members_can_update_protected_branches_setting, Enums::EnterpriseEnabledDisabledSettingValue, description: "The setting value for whether members with admin permissions for repositories can update protected branches.", null: false

      def members_can_update_protected_branches_setting
        ensure_business_can_use_api!(@object)
        business_full_plan_required!(@object)

        if !@object.members_can_update_protected_branches_policy?
          T.must(Enums::EnterpriseEnabledDisabledSettingValue.values["NO_POLICY"]).value
        elsif @object.members_can_update_protected_branches?
          T.must(Enums::EnterpriseEnabledDisabledSettingValue.values["ENABLED"]).value
        else
          T.must(Enums::EnterpriseEnabledDisabledSettingValue.values["DISABLED"]).value
        end
      end

      field :members_can_update_protected_branches_setting_organizations, Connections.define(Objects::Organization), description: "A list of enterprise organizations configured with the provided members can update protected branches setting value.", connection: true, null: false do
        argument :value, Boolean, "The setting value to find organizations for.", required: true
        argument :order_by, Inputs::OrganizationOrder,
                 "Ordering options for organizations with this setting.",
                 required: false, default_value: { field: "login", direction: "ASC" }
      end

      def members_can_update_protected_branches_setting_organizations(value:, order_by:)
        ensure_business_can_use_api!(@object)
        business_full_plan_required!(@object)

        object.members_can_update_protected_branches_setting_organizations \
          value: value,
          order_by_field: order_by&.dig(:field),
          order_by_direction: order_by&.dig(:direction)
      end

      field :members_can_delete_repositories_setting, Enums::EnterpriseEnabledDisabledSettingValue, description: "The setting value for whether members with admin permissions for repositories can delete or transfer repositories.", null: false

      def members_can_delete_repositories_setting
        ensure_business_can_use_api!(@object)
        business_full_plan_required!(@object)

        if !@object.members_can_delete_repositories_policy?
          T.must(Enums::EnterpriseEnabledDisabledSettingValue.values["NO_POLICY"]).value
        elsif @object.members_can_delete_repositories?
          T.must(Enums::EnterpriseEnabledDisabledSettingValue.values["ENABLED"]).value
        else
          T.must(Enums::EnterpriseEnabledDisabledSettingValue.values["DISABLED"]).value
        end
      end

      field :members_can_delete_repositories_setting_organizations, Connections.define(Objects::Organization), description: "A list of enterprise organizations configured with the provided members can delete repositories setting value.", connection: true, null: false do
        argument :value, Boolean, "The setting value to find organizations for.", required: true
        argument :order_by, Inputs::OrganizationOrder,
                 "Ordering options for organizations with this setting.",
                 required: false, default_value: { field: "login", direction: "ASC" }
      end

      def members_can_delete_repositories_setting_organizations(value:, order_by:)
        ensure_business_can_use_api!(@object)
        business_full_plan_required!(@object)

        object.members_can_delete_repositories_setting_organizations \
          value: value,
          order_by_field: order_by&.dig(:field),
          order_by_direction: order_by&.dig(:direction)
      end

      field :members_can_delete_issues_setting, Enums::EnterpriseEnabledDisabledSettingValue, description: "The setting value for whether members with admin permissions for repositories can delete issues.", null: false

      def members_can_delete_issues_setting
        ensure_business_can_use_api!(@object)
        business_full_plan_required!(@object)

        if !@object.members_can_delete_issues_policy?
          T.must(Enums::EnterpriseEnabledDisabledSettingValue.values["NO_POLICY"]).value
        elsif @object.members_can_delete_issues?
          T.must(Enums::EnterpriseEnabledDisabledSettingValue.values["ENABLED"]).value
        else
          T.must(Enums::EnterpriseEnabledDisabledSettingValue.values["DISABLED"]).value
        end
      end

      field :members_can_delete_issues_setting_organizations, Connections.define(Objects::Organization), description: "A list of enterprise organizations configured with the provided members can delete issues setting value.", connection: true, null: false do
        argument :value, Boolean, "The setting value to find organizations for.", required: true
        argument :order_by, Inputs::OrganizationOrder,
                 "Ordering options for organizations with this setting.",
                 required: false, default_value: { field: "login", direction: "ASC" }
      end

      def members_can_delete_issues_setting_organizations(value:, order_by:)
        ensure_business_can_use_api!(@object)
        business_full_plan_required!(@object)

        object.members_can_delete_issues_setting_organizations \
          value: value,
          order_by_field: order_by&.dig(:field),
          order_by_direction: order_by&.dig(:direction)
      end

      field :members_can_make_purchases_setting, Enums::EnterpriseMembersCanMakePurchasesSettingValue, description: "Indicates whether members of this enterprise's organizations can purchase additional services for those organizations.", null: false

      def members_can_make_purchases_setting
        ensure_business_can_use_api!(@object)
        business_full_plan_required!(@object)

        if @object.members_can_make_purchases?
          T.must(Enums::EnterpriseMembersCanMakePurchasesSettingValue.values["ENABLED"]).value
        else
          T.must(Enums::EnterpriseMembersCanMakePurchasesSettingValue.values["DISABLED"]).value
        end
      end

      field :allow_private_repository_forking_setting, Enums::EnterpriseEnabledDisabledSettingValue, description: "The setting value for whether private repository forking is enabled for repositories in organizations in this enterprise.", null: false

      def allow_private_repository_forking_setting
        ensure_business_can_use_api!(@object)
        business_full_plan_required!(@object)

        if !@object.allow_private_repository_forking_policy?
          T.must(Platform::Enums::EnterpriseEnabledDisabledSettingValue.values["NO_POLICY"]).value
        elsif @object.allow_private_repository_forking?
          T.must(Platform::Enums::EnterpriseEnabledDisabledSettingValue.values["ENABLED"]).value
        else
          T.must(Platform::Enums::EnterpriseEnabledDisabledSettingValue.values["DISABLED"]).value
        end
      end

      field :allow_private_repository_forking_setting_policy_value, Enums::EnterpriseAllowPrivateRepositoryForkingPolicyValue, description: "The value for the allow private repository forking policy on the enterprise.", null: true

      def allow_private_repository_forking_setting_policy_value
        ensure_business_can_use_api!(@object)
        business_full_plan_required!(@object)

        return nil if !@object.allow_private_repository_forking_policy? || !@object.allow_private_repository_forking?

        policy_value = @object.get_private_repository_forking_policy
        return nil unless policy_value

        T.must(Enums::EnterpriseAllowPrivateRepositoryForkingPolicyValue.values[policy_value.upcase]).value
      end

      field :allow_private_repository_forking_setting_organizations, Connections.define(Objects::Organization), description: "A list of enterprise organizations configured with the provided private repository forking setting value.", connection: true, null: false do
        argument :value, Boolean, "The setting value to find organizations for.", required: true
        argument :order_by, Inputs::OrganizationOrder,
                 "Ordering options for organizations with this setting.",
                 required: false, default_value: { field: "login", direction: "ASC" }
      end

      def allow_private_repository_forking_setting_organizations(value:, order_by:)
        ensure_business_can_use_api!(@object)
        business_full_plan_required!(@object)

        object.allow_private_repository_forking_setting_organizations \
          value: value,
          order_by_field: order_by&.dig(:field),
          order_by_direction: order_by&.dig(:direction)
      end


      field :repository_deploy_key_setting, Enums::EnterpriseEnabledDisabledSettingValue, description: "The setting value for whether deploy keys are enabled for repositories in organizations in this enterprise.", null: false

      def repository_deploy_key_setting
        ensure_business_can_use_api!(@object)
        business_full_plan_required!(@object)

        if @object.deploy_key_policy_unset?
          T.must(Enums::EnterpriseEnabledDisabledSettingValue.values["NO_POLICY"]).value
        elsif @object.deploy_key_policy_enabled?
          T.must(Enums::EnterpriseEnabledDisabledSettingValue.values["ENABLED"]).value
        else
          T.must(Enums::EnterpriseEnabledDisabledSettingValue.values["DISABLED"]).value
        end
      end

      field :repository_deploy_key_setting_organizations, Connections.define(Objects::Organization), description: "A list of enterprise organizations configured with the provided deploy keys setting value.", connection: true, null: false do
        argument :value, Boolean, "The setting value to find organizations for.", required: true
        argument :order_by, Inputs::OrganizationOrder,
                  "Ordering options for organizations with this setting.",
                  required: false, default_value: { field: "login", direction: "ASC" }
      end

      def repository_deploy_key_setting_organizations(value:, order_by:)
        ensure_business_can_use_api!(@object)
        business_full_plan_required!(@object)

        object.repository_deploy_key_setting_organizations \
          value: value,
          order_by_field: order_by&.dig(:field),
          order_by_direction: order_by&.dig(:direction)
      end

      field :members_can_view_dependency_insights_setting, Enums::EnterpriseEnabledDisabledSettingValue, description: "The setting value for whether members can view dependency insights.", null: false

      def members_can_view_dependency_insights_setting
        ensure_business_can_use_api!(@object)
        business_full_plan_required!(@object)

        if !@object.members_can_view_dependency_insights_policy?
          T.must(Enums::EnterpriseEnabledDisabledSettingValue.values["NO_POLICY"]).value
        elsif @object.members_can_view_dependency_insights?
          T.must(Enums::EnterpriseEnabledDisabledSettingValue.values["ENABLED"]).value
        else
          T.must(Enums::EnterpriseEnabledDisabledSettingValue.values["DISABLED"]).value
        end
      end

      field :members_can_view_dependency_insights_setting_organizations, Connections.define(Objects::Organization), description: "A list of enterprise organizations configured with the provided members can view dependency insights setting value.", connection: true, null: false do
        argument :value, Boolean, "The setting value to find organizations for.", required: true
        argument :order_by, Inputs::OrganizationOrder,
                 "Ordering options for organizations with this setting.",
                 required: false, default_value: { field: "login", direction: "ASC" }
      end

      def members_can_view_dependency_insights_setting_organizations(value:, order_by:)
        ensure_business_can_use_api!(@object)
        business_full_plan_required!(@object)

        object.members_can_view_dependency_insights_setting_organizations \
          value: value,
          order_by_field: order_by&.dig(:field),
          order_by_direction: order_by&.dig(:direction)
      end

      # fields to help drive the business 2FA confirmation modal
      field :two_factor_required_setting, Enums::EnterpriseEnabledSettingValue, description: "The setting value for whether the enterprise requires two-factor authentication for its organizations and users.", null: false

      def two_factor_required_setting
        if @object.two_factor_requirement_enabled?
          T.must(Enums::EnterpriseEnabledSettingValue.values["ENABLED"]).value
        else
          T.must(Enums::EnterpriseEnabledSettingValue.values["NO_POLICY"]).value
        end
      end

      field :two_factor_required_setting_organizations, Connections.define(Objects::Organization), description: "A list of enterprise organizations configured with the two-factor authentication setting value.", connection: true, null: false do
        argument :value, Boolean, "The setting value to find organizations for.", required: true
        argument :order_by, Inputs::OrganizationOrder,
                 "Ordering options for organizations with this setting.",
                 required: false, default_value: { field: "login", direction: "ASC" }
      end

      def two_factor_required_setting_organizations(value:, order_by:)
        object.two_factor_required_organizations \
          value: value,
          order_by_field: order_by&.dig(:field),
          order_by_direction: order_by&.dig(:direction)
      end

      field :affiliated_users_with_two_factor_disabled_exist, Boolean, description: "Whether or not affiliated users with two-factor authentication disabled exist in the enterprise.", null: false

      def affiliated_users_with_two_factor_disabled_exist
        @object.async_organizations.then do
          @object.affiliated_users_with_two_factor_disabled_exist?
        end
      end

      field :affiliated_users_with_two_factor_disabled, resolver: Resolvers::EnterpriseAffiliatedUsersWithTwoFactorDisabled, description: "A list of users in the enterprise who currently have two-factor authentication disabled.", connection: true, exempt_from_spam_filter_check: true

      field :is_updating_two_factor_requirement, Boolean, description: "Whether the two-factor authentication requirement is currently being enforced.", null: false

      def is_updating_two_factor_requirement
        @object.async_organizations.then do
          @object.updating_two_factor_requirement?
        end
      end

      field :two_factor_disallowed_methods_setting, Enums::EnterpriseDisallowedMethodsSettingValue, description: "The setting value for what methods of two-factor authentication the enterprise prevents its users from having.", null: false

      def two_factor_disallowed_methods_setting
        if @object.get_two_factor_disallowed_methods == Configurable::TwoFactorDisallowedMethods::INSECURE_METHODS
          T.must(Enums::EnterpriseDisallowedMethodsSettingValue.values["INSECURE"]).value
        else
          T.must(Enums::EnterpriseDisallowedMethodsSettingValue.values["NO_POLICY"]).value
        end
      end

      field :saml_identity_provider, Objects::EnterpriseIdentityProvider,
        method: :async_saml_provider,
        description: "The SAML Identity Provider for the enterprise.", null: true

      field :saml_identity_provider_setting_organizations, Connections.define(Objects::Organization),
        description: "A list of enterprise organizations configured with the SAML single sign-on setting value.",
        connection: true, null: false do
        argument :value, Enums::IdentityProviderConfigurationState,
          "The setting value to find organizations for.", required: true
        argument :order_by, Inputs::OrganizationOrder,
          "Ordering options for organizations with this setting.",
          required: false, default_value: { field: "login", direction: "ASC" }
      end

      def saml_identity_provider_setting_organizations(value:, order_by:)
        object.saml_configured_organizations \
          value: value,
          order_by_field: order_by&.dig(:field),
          order_by_direction: order_by&.dig(:direction)
      rescue ArgumentError => e
        raise Platform::Errors::Internal, e.message
      end

      field :oidc_provider, Objects::OIDCProvider,
        method: :async_oidc_provider,
        description: "The OIDC Identity Provider for the enterprise.",
        null: true,
        visibility: { public: { environments: [:dotcom] }, internal: { environments: [:enterprise] } }

      field :enterprise_server_installations, Connections.define(Objects::EnterpriseServerInstallation),
        description: "Enterprise Server installations owned by the enterprise.",
        visibility: { public: { environments: [:dotcom] }, internal: { environments: [:enterprise] } },
        connection: true, null: false do
        argument :connected_only, Boolean,
          "Whether or not to only return installations discovered via GitHub Connect.",
          required: false, default_value: false
        argument :order_by, Inputs::EnterpriseServerInstallationOrder,
          "Ordering options for Enterprise Server installations returned.",
          required: false, default_value: { field: "host_name", direction: "ASC" }
      end

      def enterprise_server_installations(connected_only: false, order_by: nil)
        business_full_plan_required!(@object)

        return EnterpriseInstallation.none unless context[:permission].can_list_enterprise_installations?(object)

        installations = object.enterprise_installations

        unless order_by.nil?
          installations = installations.order "enterprise_installations.#{order_by[:field]} #{order_by[:direction]}"
        end

        if connected_only
          installations = ArrayWrapper.new(installations.select(&:connected?))
        end
        installations
      end

      field :ip_allow_list_enabled_setting,
        Enums::IpAllowListEnabledSettingValue,
        description: "The setting value for whether the enterprise has an IP allow list enabled.",
        null: false

      def ip_allow_list_enabled_setting
        if @object.ip_allowlist_enabled?
          T.must(Enums::IpAllowListEnabledSettingValue.values["ENABLED"]).value
        else
          T.must(Enums::IpAllowListEnabledSettingValue.values["DISABLED"]).value
        end
      end

      field :ip_allow_list_for_installed_apps_enabled_setting,
        Enums::IpAllowListForInstalledAppsEnabledSettingValue,
        description: "The setting value for whether the enterprise has IP allow list configuration for installed GitHub Apps enabled.",
        null: false

      def ip_allow_list_for_installed_apps_enabled_setting
        if @object.ip_allowlist_app_access_enabled?
          T.must(Enums::IpAllowListForInstalledAppsEnabledSettingValue.values["ENABLED"]).value
        else
          T.must(Enums::IpAllowListForInstalledAppsEnabledSettingValue.values["DISABLED"]).value
        end
      end

      field :ip_allow_list_entries, Connections.define(Objects::IpAllowListEntry),
        description: "The IP addresses that are allowed to access resources owned by the enterprise. Visible to enterprise owners or enterprise owners' personal access tokens (classic) with admin:enterprise scope.",
        connection: true, null: false do
        argument :order_by, Inputs::IpAllowListEntryOrder,
          "Ordering options for IP allow list entries returned.",
          required: false, default_value: { field: "allow_list_value", direction: "ASC" }
      end

      def ip_allow_list_entries(order_by: nil)
        entries = object.ip_allowlist_entries

        unless order_by.nil?
          entries = entries.order "#{order_by[:field]} #{order_by[:direction]}"
        end

        entries
      end

      field :domains, Connections.define(Objects::VerifiableDomain),
        description: "A list of domains owned by the enterprise. Visible to enterprise owners or enterprise owners' personal access tokens (classic) with admin:enterprise scope.",
        connection: true, null: false do
        argument :is_verified, Boolean,
          "Filter whether or not the domain is verified.",
          required: false, default_value: nil
        argument :is_approved, Boolean,
          "Filter whether or not the domain is approved.",
          required: false, default_value: nil
        argument :order_by, Inputs::VerifiableDomainOrder,
          "Ordering options for verifiable domains returned.",
          required: false, default_value: { field: "domain", direction: "ASC" }
      end

      def domains(is_verified: nil, is_approved: nil, order_by: nil)
        scope = object.verifiable_domains
        if is_verified == true
          scope = scope.verified
        elsif is_verified == false
          scope = scope.unverified
        end

        if is_approved == true
          scope = scope.approved
        elsif is_approved == false
          scope = scope.unapproved
        end

        unless order_by.nil?
          scope = scope.reorder "#{order_by[:field]} #{order_by[:direction]}"
        end

        scope
      end

      field :notification_delivery_restriction_enabled_setting,
        Enums::NotificationRestrictionSettingValue,
        description: "Indicates if email notification delivery for this enterprise is restricted to verified or approved domains.",
        visibility: {
          public: { environments: [:dotcom, :enterprise] },
        },
        null: false

      def notification_delivery_restriction_enabled_setting
        if object.restrict_notifications_to_verified_domains?
          T.must(Enums::NotificationRestrictionSettingValue.values["ENABLED"]).value
        else
          T.must(Enums::NotificationRestrictionSettingValue.values["DISABLED"]).value
        end
      end
    end
  end
end
