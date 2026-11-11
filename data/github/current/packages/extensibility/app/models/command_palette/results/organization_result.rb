# typed: true
# frozen_string_literal: true

module CommandPalette
  module Results
    class OrganizationResult < Result
      def self.type
        Organization
      end

      def self.create(org, priority, context, group = nil)
        # orgs always get a weight to be above users
        weighted_priority = PRIORITY_WEIGHTS[:org_default]

        # orgs the user is affiliated with get higher weights
        affiliated_org_roles = context&.current_user_affiliated_orgs&.dig(org)
        weighted_priority = max_role_based_weight(affiliated_org_roles) if affiliated_org_roles.present?

        priority = priority + weighted_priority

        new(
          priority: priority,
          title: org.display_login,
          scope: ResultScope.new(org),
          icon: Icons::Avatar.new(url: org.primary_avatar_url, alt: "@#{org.display_login}"),
          action: Actions::JumpToOrgAction.new(path: user_path(org)),
          group: group || :organizations,
          object: org
        )
      end

      def self.max_role_based_weight(roles)
        # you can have multiple roles in an org
        roles.map do |role|
          PRIORITY_WEIGHTS[role] || PRIORITY_WEIGHTS[:org_default]
        end.max
      end
    end
  end
end
