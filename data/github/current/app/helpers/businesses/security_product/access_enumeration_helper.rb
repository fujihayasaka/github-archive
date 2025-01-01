# typed: true
# frozen_string_literal: true

module Businesses
  module SecurityProduct
    module AccessEnumerationHelper
      extend T::Helpers
      extend T::Sig

      abstract!

      # This mixin is used by both the UI and API, unfortunately there is no closer ancestor than `Object`.
      # Declaring this makes it possible to reference `self` without needing to bind it as `T.untyped` in each method.
      requires_ancestor { Object }

      sig { abstract.returns(User) }
      def current_user; end

      sig { abstract.returns(T::Boolean) }
      def logged_in?; end

      # @return [Array<Organization>, Array<Organization>] CAP–authorized and unauthorized organizations.
      def authorized_and_unauthorized_organizations(business_id, cap_filter:, fgp:)
        GitHub.dogstats.distribution_time("advanced_security.authorized_and_unauthorized_organizations.dist", tags: ["class:#{self.class.name&.underscore}"]) do
          return [[], []] unless logged_in?

          non_cap_filtered_orgs = non_cap_filtered_organizations(business_id, fgp: fgp)

          [
            cap_filter.authorized_resources(non_cap_filtered_orgs),
            cap_filter.unauthorized_resources(non_cap_filtered_orgs)
          ]
        end
      end

      def organization_ids_accessible_via_fgp(organization_ids, fgp:)
        # The first query hits the IAM database cluster and gets a list of team and org IDs that have the role assigned to them.
        # This query joins user_roles, roles, and role_permissions tables, as the relationship is not direct.

        GitHub.dogstats.count "advanced_security.get_user_security_manager_teams_on_organizations.organizations.count", organization_ids.length

        allowed_teams = T.let([], T::Array[[Integer, Integer]])
        GitHub.dogstats.distribution_time "advanced_security.query_teams_with_secret_scanning_alerts_access.duration" do
          allowed_teams = organization_ids.in_groups_of(1000, false).flat_map do |batch|
            UserRole.joins(role: [:permissions]).where(
              role_permissions: { action: fgp },
              target_type: "Organization",
              target_id: batch,
              actor_type: "Team"
            ).pluck(:actor_id, :target_id)
          end
        end

        # Second query hits the Abilities database cluster and filters above list
        # to the teams that the user is member of (directly or indirectly)
        # This matches behavior of descendant_or_self_member_ids_for
        user_team_ids = T.let([], T::Array[Integer])
        GitHub.dogstats.distribution_time "advanced_security.query_user_membership_in_teams_with_secret_scanning_alerts_access.duration" do
          user_team_ids = Ability.where(subject_id: allowed_teams.map { |team_id,| team_id },
                subject_type: "Team", actor_type: "User", actor_id: current_user.id)
              .where("priority <= ?", Ability.priorities[:direct])
              .distinct.pluck(:subject_id).to_set
        end

        allowed_teams.select { |team_id, _org_id| user_team_ids.include?(team_id) }.map { |_team_id, org_id| org_id }.uniq.to_a
      end

      private

      # Return org IDs for which the user is either an admin or on a team with org access.
      # This DOES NOT take into account CAP policies (whether or not the user is currently authenticated with those orgs).
      def non_cap_filtered_organizations(business_id, fgp:)
        return [] unless logged_in?

        business = Business.find(business_id)
        business_org_ids = business.organization_ids
        user_admin_org_ids = Ability.user_admin_on_organizations(actor_id: current_user.id).pluck(:subject_id)
        team_accessible_org_ids = organization_ids_accessible_via_fgp(business_org_ids, fgp: fgp)
        ids = business_org_ids & (user_admin_org_ids + team_accessible_org_ids).uniq

        is_business_owner = business.owner?(current_user)
        is_admin_of_some_orgs = user_admin_org_ids.size > 0
        is_security_manager_of_some_orgs = user_admin_org_ids.size < ids.size

        GitHub.dogstats.distribution(
          "advanced_security.non_cap_filtered_organizations.dist",
          ids.size,
          tags: [
            "class:#{self.class.name&.underscore}",
            "is_user_business_owner:#{is_business_owner}",
            "is_user_admin_of_some_orgs:#{is_admin_of_some_orgs}",
            "is_user_security_manager_of_some_orgs:#{is_security_manager_of_some_orgs}"
          ],
        )

        ids.each_slice(1_000).flat_map { |batch| Organization.where(id: batch) }
      end
    end
  end
end
