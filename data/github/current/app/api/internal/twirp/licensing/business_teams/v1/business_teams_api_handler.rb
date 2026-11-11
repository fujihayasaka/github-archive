# typed: true
# frozen_string_literal: true

require "monolith-twirp-licensing-business_teams"

module Api::Internal::Twirp::Licensing
  module BusinessTeams
    module V1
      # Handler for the MonolithTwirp::Licensing::BusinessTeams::V1::BusinessTeamsAPIService
      #
      # This handler provides endpoints for querying Business Team organization assignments,
      # used by Licensify for reconciliation and debugging operations.
      class BusinessTeamsAPIHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: ["licensing"]
        handles_service MonolithTwirp::Licensing::BusinessTeams::V1::BusinessTeamsAPIService

        # Public: Implementation of the GetBusinessTeamOrgAssignments Twirp RPC.
        #
        # Returns the organizations that a Business Team is assigned to.
        # Used by Licensify for reconciliation and debugging operations.
        #
        # req - The Twirp request as a MonolithTwirp::Licensing::BusinessTeams::V1::GetBusinessTeamOrgAssignmentsRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a
        # MonolithTwirp::Licensing::BusinessTeams::V1::GetBusinessTeamOrgAssignmentsResponse, or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::Licensing::BusinessTeams::V1::GetBusinessTeamOrgAssignmentsRequest,
            env: T::Hash[T.untyped, T.untyped],
          ).returns(T.any(MonolithTwirp::Licensing::BusinessTeams::V1::GetBusinessTeamOrgAssignmentsResponse, Twirp::Error))
        end
        def get_business_team_org_assignments(req, env)
          # Validate input
          unless business_team_id = id_argument(T.unsafe(req).business_team_id)
            return Twirp::Error.invalid_argument("business_team_id must be a positive integer", argument: "business_team_id")
          end

          business_team = BusinessTeam.find_by(id: business_team_id)

          unless business_team
            return Twirp::Error.not_found("Business Team not found: #{business_team_id}")
          end

          ::Failbot.push "gh.business_team.id": business_team_id

          build_org_assignments_response(business_team)
        end

        private

        sig do
          params(
            business_team: BusinessTeam
          ).returns(MonolithTwirp::Licensing::BusinessTeams::V1::GetBusinessTeamOrgAssignmentsResponse)
        end
        def build_org_assignments_response(business_team)
          customer_id = business_team.business&.customer_id || 0

          case business_team.organization_selection_type.to_sym
          when :all
            # Wildcard assignment - all orgs in the enterprise
            T.unsafe(MonolithTwirp::Licensing::BusinessTeams::V1::GetBusinessTeamOrgAssignmentsResponse).new(
              business_team_id: business_team.id,
              customer_id: customer_id,
              organization_ids: [],
              all_orgs: true
            )
          when :selected
            # Specific org assignments - only include active (non-deleted) organizations
            org_ids = business_team.selected_organizations.pluck(:id)
            T.unsafe(MonolithTwirp::Licensing::BusinessTeams::V1::GetBusinessTeamOrgAssignmentsResponse).new(
              business_team_id: business_team.id,
              customer_id: customer_id,
              organization_ids: org_ids,
              all_orgs: false
            )
          else
            # Disabled or unknown - no orgs assigned
            T.unsafe(MonolithTwirp::Licensing::BusinessTeams::V1::GetBusinessTeamOrgAssignmentsResponse).new(
              business_team_id: business_team.id,
              customer_id: customer_id,
              organization_ids: [],
              all_orgs: false
            )
          end
        end
      end
    end
  end
end
