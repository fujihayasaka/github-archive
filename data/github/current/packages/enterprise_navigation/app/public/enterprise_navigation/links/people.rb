# typed: strict
# frozen_string_literal: true

module EnterpriseNavigation
  module Links
    module People
      extend T::Helpers
      include GitHub::Memoizer
      include UrlHelpers
      include EnterpriseNavigation::Links::SharedDependency

      sig { returns T::Array[EnterpriseNavigation::Group] }
      memoize def people_menu_groups
        [people_sub_group, enterprise_roles_group, organization_roles_group, invitations_sub_group, suspended_group]
      end

      sig { returns T::Array[EnterpriseNavigation::Link] }
      memoize def people_menu_items
        people_menu_groups.flat_map(&:links)
      end

      sig { returns EnterpriseNavigation::Group }
      memoize def people_sub_group
        menu_items = []
        menu_items << members_item if read_enterprise_admins_and_members?
        menu_items << administrators_item if read_enterprise_admins_and_members?

        if business_owner? || member_of_owned_org?
          menu_items << enterprise_teams_item if business&.enterprise_teams_enabled? || BusinessTeam.enabled_for_enterprise?(business: business)
          menu_items << enterprise_security_managers_item if EnterpriseTeam.enabled_for_organization_security_manager?(business)
        end
        menu_items << outside_collaborators_item if outside_collaborators_sub_menu_item_available?

        EnterpriseNavigation::Group.new(
          links: menu_items
        )
      end

      sig { returns EnterpriseNavigation::Group }
      memoize def organization_roles_group
        menu_items = []
        menu_items << enterprise_organization_roles_item if user_can_see_enterprise_organization_roles?

        EnterpriseNavigation::Group.new(
          links: menu_items,
          type: EnterpriseNavigation::GroupType::FLAT
        )
      end

      sig { returns EnterpriseNavigation::Group }
      memoize def enterprise_roles_group
        menu_items = []
        menu_items << custom_enterprise_role_management_menu_item if user_can_see_custom_enterprise_roles?
        menu_items << custom_enterprise_role_assignments_menu_item if user_can_see_custom_enterprise_roles?

        EnterpriseNavigation::Group.new(
          name: "Enterprise roles",
          links: menu_items,
          type: EnterpriseNavigation::GroupType::FOLDING_WITH_DIVIDER,
          icon: :globe
        )
      end

      sig { returns EnterpriseNavigation::Group }
      memoize def invitations_sub_group
        menu_items = []
        menu_items << pending_invitation_item if user_can_see_pending_or_failed_invitations?
        menu_items << failed_invitation_item if user_can_see_pending_or_failed_invitations?
        EnterpriseNavigation::Group.new(
          links: menu_items
        )
      end

      sig { returns EnterpriseNavigation::Group }
      memoize def suspended_group
        menu_items = []

        menu_items << suspended_members_item if read_enterprise_admins_and_members? && scim_managed_enterprise?

        EnterpriseNavigation::Group.new(
          links: menu_items
        )
      end

      sig { returns T::Boolean }
      memoize def read_enterprise_admins_and_members?
        if business&.feature_enabled?(:support_enterprise_admins_and_members)
          permission_grants[:read_enterprise_admins_and_members] || false
        else
          business_owner?
        end
      end

      sig { returns T::Boolean }
      memoize def read_enterprise_members?
        business_owner? || business&.actor_can_read_members?(user, skip_owner_check: true) || false
      end

      sig { returns T::Boolean }
      memoize def scim_managed_enterprise?
        business&.enterprise_server_scim_enabled? ||
        business&.enterprise_managed_user_enabled?
      end

      sig { returns T::Boolean }
      memoize def outside_collaborators_sub_menu_item_available?
        return false unless read_enterprise_members?
        return false if scim_managed_enterprise? &&
                        !business&.emu_repository_collaborators_enabled?
        return false if business&.seats_plan_basic?
        true
      end

      sig { returns T::Boolean }
      memoize def user_can_see_enterprise_organization_roles?
        return false unless business&.custom_organization_roles_supported?
        return true if user&.site_admin?

        permission_grants[:read_enterprise_custom_org_role] || false
      end

      sig { returns T::Boolean }
      memoize def user_can_see_custom_enterprise_roles?
        return false unless @business&.custom_enterprise_roles_supported?
        return true if user&.site_admin?

        permission_grants[:read_enterprise_custom_enterprise_role] || false
      end

      sig { returns T::Boolean }
      memoize def user_can_see_pending_or_failed_invitations?
        return false if GitHub.single_business_environment? ||
        business&.enterprise_managed_user_enabled?

        business_owner? || business&.actor_can_read_invitations?(user, skip_owner_check: true) || false
      end

      sig { returns EnterpriseNavigation::Link }
      memoize def members_item
        EnterpriseNavigation::Link.new(
          link_name: "Members",
          link_path: people_enterprise_path(business),
          highlight: %i(
            business_people
          ),
          icon: :people
        )
      end

      sig { returns EnterpriseNavigation::Link }
      memoize def administrators_item
        EnterpriseNavigation::Link.new(
          link_name: "Administrators",
          link_path: enterprise_admins_path(business),
          highlight: %i(
            business_admins
          ),
          icon: :law
        )
      end

      sig { returns EnterpriseNavigation::Link }
      memoize def enterprise_teams_item
        EnterpriseNavigation::Link.new(
          link_name: "Enterprise teams",
          link_path: enterprise_teams_path(business),
          highlight: %i(
            business_teams
            create_enterprise_teams
            edit_enterprise_teams
          ),
          icon: :people
        )
      end

      sig { returns EnterpriseNavigation::Link }
      memoize def enterprise_security_managers_item
        EnterpriseNavigation::Link.new(
          link_name: "Security managers",
          link_path: enterprise_security_managers_path(business),
          highlight: %i(business_security_managers),
          icon: :"shield-lock"
        )
      end

      sig { returns EnterpriseNavigation::Link }
      memoize def outside_collaborators_item
        EnterpriseNavigation::Link.new(
          link_name: outside_collaborators_verbiage(business).capitalize,
          link_path: enterprise_outside_collaborators_path(business),
          highlight: %i(
            business_outside_collaborators
          ),
          icon: :"cross-reference"
        )
      end

      sig { returns EnterpriseNavigation::Link }
      memoize def suspended_members_item
        EnterpriseNavigation::Link.new(
          link_name: "Suspended",
          link_path: enterprise_suspended_members_path(business),
          highlight: %i(
            business_suspended_members
          ),
          icon: :"circle-slash"
        )
      end

      sig { returns EnterpriseNavigation::Link }
      memoize def enterprise_organization_roles_item
        EnterpriseNavigation::Link.new(
          link_name: "Organization roles",
          link_path: enterprise_organization_roles_path(business),
          highlight: %i(
            business_organization_roles
          ),
          icon: :"organization"
        )
      end

      sig { returns EnterpriseNavigation::Link }
      memoize def pending_invitation_item
        EnterpriseNavigation::Link.new(
          link_name: "Invitations",
          link_path: enterprise_pending_members_path(business),
          highlight: %i(
            business_pending_invitations
          ),
          icon: :"person-add"
        )
      end

      sig { returns EnterpriseNavigation::Link }
      memoize def failed_invitation_item
        EnterpriseNavigation::Link.new(
          link_name: "Failed invitations",
          link_path: enterprise_failed_invitations_path(business),
          highlight: %i(
            business_failed_invitations
          ),
          icon: :"no-entry"
        )
      end

      sig { returns EnterpriseNavigation::Link }
      memoize def custom_enterprise_role_management_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Role management",
          link_path: enterprise_roles_path(business),
          highlight: %i(
            enterprise_role_management
          ),
        )
      end

      sig { returns EnterpriseNavigation::Link }
      memoize def custom_enterprise_role_assignments_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Role assignments",
          link_path: enterprise_role_assignments_path(business),
          highlight: %i(
            enterprise_role_assignments
          ),
        )
      end
    end
  end
end
