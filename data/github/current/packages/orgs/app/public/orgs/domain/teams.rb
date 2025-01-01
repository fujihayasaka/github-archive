# typed: strict
# frozen_string_literal: true

module Orgs
  class Domain
    class Teams < GH::Domain::Base

      sig { params(id: Integer).returns(T.nilable(ITeam)) }
      def by_id(id)  # rubocop:disable GitHub/DocumentationDomainMethod
        return nil if id <= 0

        Team.find_by(id: id.to_i)
      end

      sig { params(organization_id: Integer).returns(T::Array[Integer]) }
      def business_team_ids_for_assigned_orgs(organization_id:) # rubocop:disable GitHub/DocumentationDomainMethod
        return [] if organization_id <= 0

        # look up business_id for given org_id
        business_org_membership = Business::OrganizationMembership.find_by(organization_id: organization_id)
        return [] unless business_org_membership
        business_id = business_org_membership.business_id

        # TODO: ensure these queries are batched to avoid unbounded queries
        # TODO: replace abilities query with dependency on the authz domain
        all_orgs_team_ids = BusinessTeam.where(business_id: business_id, organization_selection_type: :all).pluck(:id)
        selected_org_team_ids = BusinessTeamOrgAssignment.where(organization_id: organization_id).pluck(:team_id)
        all_orgs_team_ids + selected_org_team_ids
      end

      sig { params(business_id: Integer, user_id: Integer).returns(T::Array[Integer]) }
      def business_team_ids_for(business_id:, user_id:)  # rubocop:disable GitHub/DocumentationDomainMethod
        return [] if business_id <= 0
        return [] if user_id <= 0

        # TODO: ensure these queries are batched to avoid unbounded queries
        # TODO: replace abilities query with dependency on the authz domain
        team_ids = Ability.where(subject_type: "BusinessTeam", actor_type: "User", actor_id: user_id).pluck(:subject_id)
        BusinessTeam.where(business_id: business_id, id: team_ids).pluck(:id)
      end

      sig { params(user_id: Integer, organization_id: Integer).returns(T::Array[Integer]) }
      def business_team_ids_with_assigned_orgs_for(user_id:, organization_id:)  # rubocop:disable GitHub/DocumentationDomainMethod
        return [] if organization_id <= 0
        return [] if user_id <= 0

        # look up business_id for given org_id
        business_org_membership = Business::OrganizationMembership.find_by(organization_id: organization_id)
        return [] unless business_org_membership
        business_id = business_org_membership.business_id

        # TODO: ensure these queries are batched to avoid unbounded queries
        # TODO: replace abilities query with dependency on the authz domain
        team_ids = Ability.where(subject_type: "BusinessTeam", actor_type: "User", actor_id: user_id).pluck(:subject_id)
        all_orgs_team_ids = BusinessTeam.where(id: team_ids, business_id: business_id, organization_selection_type: :all).pluck(:id)
        selected_org_team_ids = BusinessTeamOrgAssignment.where(organization_id: organization_id, team_id: team_ids).pluck(:team_id)
        all_orgs_team_ids + selected_org_team_ids
      end

      sig { params(user_ids: T::Array[Integer], organization_id: Integer).returns(T::Array[Integer]) }
      def business_team_user_ids(user_ids:, organization_id:)  # rubocop:disable GitHub/DocumentationDomainMethod
        return [] if organization_id <= 0
        return [] if user_ids.empty?

        # look up business_id for given org_id
        business_org_membership = Business::OrganizationMembership.find_by(organization_id: organization_id)
        return [] unless business_org_membership
        business_id = business_org_membership.business_id

        # TODO: ensure these queries are batched to avoid unbounded queries
        # TODO: replace abilities query with dependency on the authz domain
        team_ids = Ability.where(subject_type: "BusinessTeam", actor_type: "User", actor_id: user_ids).pluck(:subject_id)
        all_orgs_team_ids = BusinessTeam.where(id: team_ids, business_id: business_id, organization_selection_type: :all).pluck(:id)
        selected_org_team_ids = BusinessTeamOrgAssignment.where(organization_id: organization_id, team_id: team_ids).pluck(:team_id)
        Ability.where(subject_type: "BusinessTeam", actor_type: "User", subject_id: all_orgs_team_ids + selected_org_team_ids, actor_id: user_ids).pluck(:actor_id)
      end

      sig { params(user_id: Integer, min_action: T.nilable(Symbol)).returns(T::Array[Integer]) }
      def business_team_org_ids_for_user(user_id:, min_action: :read) # rubocop:disable GitHub/DocumentationDomainMethod
        return [] if user_id <= 0
        # TODO: ensure these queries are batched to avoid unbounded queries
        # TODO: replace abilities query with dependency on the authz domain
        team_ids = Ability.where(subject_type: "BusinessTeam", actor_type: "User", actor_id: user_id).pluck(:subject_id)
        all_orgs_team_biz_ids = BusinessTeam.where(id: team_ids, organization_selection_type: :all).pluck(:business_id)
        all_orgs_team_org_ids = Business.where(id: all_orgs_team_biz_ids).joins(:organization_memberships).pluck(:organization_id)
        selected_org_ids = BusinessTeamOrgAssignment.where(team_id: team_ids).pluck(:organization_id)
        all_biz_team_org_ids = all_orgs_team_org_ids + selected_org_ids
        min_action_rank = Ability::ACTION_RANKING[min_action || :read]
        biz_team_orgs = Organization.preload(:business_membership).where(id: all_biz_team_org_ids)

        Configurable.preload_configuration(biz_team_orgs)
        biz_team_orgs.map do |org|
          default_permission_rank = Ability::ACTION_RANKING[org.default_repository_permission.to_sym]
          next if !default_permission_rank
          next if default_permission_rank < min_action_rank
          org.id
        end.compact.uniq
      end

      # rubocop:disable Metrics/MethodLength
      sig { params(organization_id: Integer, team_id: T.nilable(Integer), team_slug: T.nilable(String)).returns(T.nilable(ITeam)) }
      def find_team_in_organization(organization_id:, team_id: nil, team_slug: nil) # rubocop:disable GitHub/DocumentationDomainMethod
        return nil if organization_id <= 0
        return nil if !team_id&.positive? && team_slug.to_s.empty?

        # Try regular team first
        team = if team_id&.positive?
          Team.find_by(id: team_id, organization_id: organization_id)
        else
          Team.find_by(slug: team_slug, organization_id: organization_id)
        end
        return team if team

        # Try business team
        business_team = if team_id&.positive?
          BusinessTeam.find_by(id: team_id)
        else
          BusinessTeam.find_by(slug: team_slug)
        end
        return nil unless business_team

        # Check if business team is associated with this org
        business_org_membership = Business::OrganizationMembership.find_by(
          organization_id: organization_id,
          business_id: business_team.business_id
        )
        return nil unless business_org_membership

        # Verify team has access to this org (either all orgs or specifically assigned)
        return business_team if business_team.organization_selection_type.to_sym == :all

        business_team if BusinessTeamOrgAssignment.exists?(
          team_id: business_team.id,
          organization_id: organization_id
        )
      end

      sig { params(repo_id: Integer, team_ids: T.nilable(T::Array[Integer])).returns(T::Array[ITeam]) }
      def teams_for_repo(repo_id:, team_ids: nil)  # rubocop:disable GitHub/DocumentationDomainMethod
        return [] if repo_id <= 0

        # TODO: ensure these queries are batched to avoid unbounded queries
        # TODO: replace abilities query with dependency on the authz domain
        query = Ability.where(subject_type: "Repository", subject_id: repo_id)
                       .where(actor_type: %w(Team BusinessTeam))
        query = query.where(actor_id: team_ids) if team_ids&.any?

        # Get abilities grouped by actor type
        abilities = query.pluck(:actor_type, :actor_id).group_by(&:first)

        teams = []
        # Find Team records
        if abilities["Team"]
          team_ids = abilities["Team"].map(&:last)
          teams += Team.where(id: team_ids).to_a
        end

        # Find BusinessTeam records
        if abilities["BusinessTeam"]
          business_team_ids = abilities["BusinessTeam"].map(&:last)
          teams += BusinessTeam.where(id: business_team_ids).to_a
        end

        teams
      end
    end
  end
end
