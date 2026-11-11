# typed: strict
# frozen_string_literal: true

module Orgs
  class Domain
    class BusinessTeamOrgAssignments < GH::Domain::Base
      # Assigns organizations to a business team.
      #
      # Delegates to BusinessTeam#add_to_organizations which handles orchestration,
      # validation (limit checks, seat checks), and instrumentation.
      #
      # @param business_team_id [Integer] The ID of the business team to assign organizations to.
      # @param org_ids [Array<Integer>] The IDs of organizations to assign.
      # @param synchronous_orchestration [Boolean] Whether to run the orchestration synchronously.
      # @return [Team::AddOrganizationStatus] The result status of the operation.
      sig { params(business_team_id: Integer, org_ids: T::Array[Integer], synchronous_orchestration: T::Boolean).returns(Team::AddOrganizationStatus) }
      def assign_organizations(business_team_id:, org_ids:, synchronous_orchestration: false)
        business_team = BusinessTeam.find_by(id: business_team_id)
        T.must(business_team).add_to_organizations(org_ids: org_ids)
      end

      # Unassigns organizations from a business team.
      #
      # Delegates to BusinessTeam#remove_from_organizations which handles orchestration
      # and instrumentation.
      #
      # @param business_team_id [Integer] The ID of the business team to unassign organizations from.
      # @param org_ids [Array<Integer>] The IDs of organizations to unassign.
      # @param synchronous_orchestration [Boolean] Whether to run the orchestration synchronously.
      sig { params(business_team_id: Integer, org_ids: T::Array[Integer], synchronous_orchestration: T::Boolean).void }
      def unassign_organizations(business_team_id:, org_ids:, synchronous_orchestration: false)
        business_team = BusinessTeam.find_by(id: business_team_id)
        T.must(business_team).remove_from_organizations(org_ids: org_ids, synchronous_orchestration: synchronous_orchestration)
      end

      # Destroys all org assignments for a business team.
      #
      # Used when a team's organization_selection_type changes to :all or :disabled.
      #
      # @param business_team_id [Integer] The ID of the business team to clear assignments for.
      sig { params(business_team_id: Integer).void }
      def clear_all_for_team(business_team_id:)
        business_team = BusinessTeam.find_by(id: business_team_id)
        T.must(business_team).business_team_org_assignments.destroy_all
      end

      # Disassociates organizations from all business teams in a business.
      #
      # Enqueues background jobs to clear assignments and indirect org access.
      # Used during org soft-delete and org removal from a business.
      #
      # @param business_id [Integer] The ID of the business.
      # @param org_ids [Array<Integer>] The IDs of organizations to disassociate.
      sig { params(business_id: Integer, org_ids: T::Array[Integer]).void }
      def disassociate_org_from_teams(business_id:, org_ids:)
        organizations = Organization.where(id: org_ids).to_a
        BusinessTeam.disassociate_org_from_teams(business_id, organizations)
      end
    end
  end
end
