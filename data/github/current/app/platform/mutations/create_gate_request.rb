# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class CreateGateRequest < Platform::Mutations::Base
      visibility :internal
      description "Creates a gate request."

      minimum_accepted_scopes ["public_repo"]

      limit_actors_to [:github_app]

      argument :gate_id, ID, "The node ID of the gate.", required: true, as: :gate
      argument :check_run_id, ID, "The node ID of the check run id.", required: true, loads: Objects::CheckRun, as: :check_run
      argument :token, String, "The token to store for Actions Service.", required: false
      argument :state, Enums::GateRequestState, "The state of the gate request.", required: false
      argument :concluded, Boolean, "Whether the gate request is concluded or not", required: false
      argument :expires_at, Scalars::DateTime, "The time that the gate request expires at.", required: false

      resolve_tenant_context do |check_run:, **_|
        _, check_run_id = Platform::Helpers::NodeIdentification.from_global_id(check_run)
        check_run = CheckRun.find_by(id: check_run_id)

        next nil if check_run.nil?

        Repositories::Public.resolve_tenant(id: check_run.repository_id)
      end

      field :gate_request, Objects::GateRequest, "The existing gate request or a new gate request.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, **inputs)
        # No special API permissions
        permission.hidden_from_public?(self) # Update this authorization if we ever go public with this object
      end

      def resolve(check_run:, **inputs)
        # When a gate is deleted we auto-reject all gate requests. When this happens Actions Service will
        # send a post back to update the gate request. The gate is deleted, but the gate request is not, so we
        # want to use the gate_id instead of an instance of the gate to find the gate request
        _, gate_id = Platform::Helpers::NodeIdentification.from_global_id(inputs[:gate])

        gate_request = GateRequest.create_or_update_gate_request(gate_id, check_run, inputs[:token], inputs[:state], inputs[:concluded], inputs[:expires_at])
        { gate_request: gate_request }
      end
    end
  end
end
