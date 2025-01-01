# typed: true
# frozen_string_literal: true

require "monolith-twirp-actions-core"

module Api::Internal::Twirp::Actions
  module Core
    module V1
      # Handler for the MonolithTwirp::Actions::Core::V1::EnvironmentsAPIService
      class EnvironmentsAPIHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: ["launch"].freeze
        handles_service MonolithTwirp::Actions::Core::V1::EnvironmentsAPIService

        resolve_tenant_context do |req, _env|
          case req
          when MonolithTwirp::Actions::Core::V1::ResolveActionsEnvironmentRequest
            begin
              next nil unless req.repository_id&.global_id.present?

              repo_id = Platform::Helpers::NodeIdentification.from_global_id(req.repository_id&.global_id).last
              Repositories::Public.resolve_tenant(id: repo_id)
            rescue Platform::Errors::NotFound, ActiveRecord::RecordNotFound => err
              GitHub.logger.info(
                "unable to resolve tenant", {
                  :exception => err,
                  "code.namespace" => self.class.name,
                  "code.function" => __method__,
                  "gh.repo.global_id" => req.repository_id&.global_id
              })

              Twirp::Error.not_found(err.message)
            end
          when MonolithTwirp::Actions::Core::V1::GetEnvironmentRepositoryRequest
            begin
              next nil unless req.environment_id&.global_id.present?

              environment_id = Platform::Helpers::NodeIdentification.from_global_id(req.environment_id&.global_id).last
              repository_id = Environment.where(id: environment_id).pluck(:repository_id).last

              next nil if repository_id.nil?

              Repositories::Public.resolve_tenant(id: repository_id)
            rescue Platform::Errors::NotFound, ActiveRecord::RecordNotFound => err
              GitHub.logger.info(
                "unable to resolve tenant", {
                  :exception => err,
                  "code.namespace" => self.class.name,
                  "code.function" => __method__,
                  "gh.environment.global_id" => req.environment_id&.global_id
              })

              Twirp::Error.not_found(err.message)
            end
          end
        end

        # Public: Implementation of the ResolveActionsEnvironment Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Actions::Core::V1::ResolveActionsEnvironmentRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Actions::Core::V1::ResolveActionsEnvironmentResponse, or a Twirp::Error.
        def resolve_actions_environment(req, env)
          ResolveActionsEnvironment.call(req)
        end

        # Public: Implementation of the GetEnvironmentRepository Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Actions::Core::V1::GetEnvironmentRepositoryRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Actions::Core::V1::GetEnvironmentRepositoryResponse, or a Twirp::Error.
        def get_environment_repository(req, env)
          GetEnvironmentRepository.call(req)
        end
      end
    end
  end
end
