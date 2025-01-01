# typed: true
# frozen_string_literal: true

require "actions-run-service"

class Api::Internal::Twirp
  module ActionsRunService
    module Environments
      module V1
        class EnvironmentsAPIHandler < Api::Internal::Twirp::Handler
          allow_access_for :client, allowed_clients: ["actions_run_service"].freeze
          handles_service GitHub::ActionsRunService::Environments::V1::EnvironmentsAPIService
          connected_to_writing_for :create_environment

          # Public: Implementation of the GetEnvironment Twirp RPC.
          #
          # req - The Twirp request as a GitHub::ActionsRunService::Environments::V1::GetEnvironmentRequest.
          # env - The Twirp environment as a Hash.
          #
          # Returns the Twirp response as a Hash suitable for use in a
          # GitHub::ActionsRunService::Environments::V1::GetEnvironmentResponse, or a Twirp::Error.
          def get_environment(req, env)
            return Twirp::Error.invalid_argument("must be non-empty", argument: "repository_global_id") if req.repository_global_id.empty?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "name") if req.name.empty?

            begin
              type, repository_id = Platform::Helpers::NodeIdentification.from_global_id(req.repository_global_id)
            rescue Platform::Errors::NotFound
              return Twirp::Error.not_found("unresolvable repository global id", argument: "repository_global_id")
            end

            return Twirp::Error.invalid_argument("must be a repository global id", argument: "repository_global_id") unless type == "Repository"

            environment = Environment.find_by(name: req.name, repository_id: repository_id)

            unless environment.present?
              return Twirp::Error.not_found("the environment does not exist", argument: "name")
            end

            format_response(environment)
          end

          # Public: Implementation of the CreateEnvironment Twirp RPC.
          #
          # req - The Twirp request as a GitHub::ActionsRunService::Environments::V1::CreateEnvironmentRequest.
          # env - The Twirp environment as a Hash.
          #
          # Returns the Twirp response as a Hash suitable for use in a
          # GitHub::ActionsRunService::Environments::V1::CreateEnvironmentResponse, or a Twirp::Error.
          def create_environment(req, env)
            return Twirp::Error.invalid_argument("must be non-empty", argument: "repository_global_id") if req.repository_global_id.empty?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "name") if req.name.empty?

            begin
              type, repository_id = Platform::Helpers::NodeIdentification.from_global_id(req.repository_global_id)
            rescue Platform::Errors::NotFound
              return Twirp::Error.not_found("unresolvable repository global id", argument: "repository_global_id")
            end

            return Twirp::Error.invalid_argument("must be a repository global id", argument: "repository_global_id") unless type == "Repository"

            begin
              environment = Environment.create_for_repository(repository_id, req.name)
            rescue ActiveRecord::StatementInvalid
              return Twirp::Error.internal("Unable to create Environment with name '#{req.name}'")
            end

            return Twirp::Error.internal("Unable to create Environment with name '#{req.name}'") if environment.nil? || !environment.valid?

            format_response(environment)
          end

          def get_global_id(entity)
            !GitHub.enterprise? ? entity.next_global_id : entity.global_relay_id
          end

          def get_gate_type(gate)
            return :TYPE_TIMEOUT if gate.timeout?
            :TYPE_REMOTE
          end

          def format_response(environment)
            gates = []

            if FeatureFlag.vexi.enabled_or_raise?(:actions_gates_twirp_permission_fix) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
              env_gates = environment.gates_for_twirp
            else
              env_gates = environment.gates
            end

            env_gates.each do |gate|
              gates << {
                global_id: get_global_id(gate),
                database_id: gate.id,
                gate_type: get_gate_type(gate),
                timeout_in_minutes: gate.timeout,
              }
            end

            {
              environment: {
                global_id: get_global_id(environment),
                database_id: environment.id,
                name: environment.name,
                gates: gates,
              }
            }
          end
        end
      end
    end
  end
end
