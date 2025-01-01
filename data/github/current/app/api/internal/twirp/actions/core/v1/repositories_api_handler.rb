# typed: true
# frozen_string_literal: true

require "monolith-twirp-actions-core"

module Api::Internal::Twirp::Actions
  module Core
    module V1
      # Handler for the MonolithTwirp::Actions::Core::V1::RepositoriesAPIService
      class RepositoriesAPIHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: ["launch"]
        handles_service MonolithTwirp::Actions::Core::V1::RepositoriesAPIService

        resolve_tenant_context only: %i[
          check_repository_actions_status
          get_additional_workflows
          get_commit_message
          get_repository_owner_id
          get_repository_owners
          get_repository_event_details
        ] do |req, _env|
          request = T.must(req)

          repository_id = case request
          when
            MonolithTwirp::Actions::Core::V1::GetRepositoryOwnersRequest,
            MonolithTwirp::Actions::Core::V1::CheckRepositoryActionsStatusRequest,
            MonolithTwirp::Actions::Core::V1::GetRepositoryOwnerIdRequest

            request.id
          when
            MonolithTwirp::Actions::Core::V1::GetAdditionalWorkflowsRequest,
            MonolithTwirp::Actions::Core::V1::GetCommitMessageRequest,
            MonolithTwirp::Actions::Core::V1::GetRepositoryEventDetailsRequest

            request.repository_id
          end

          if repository_id.nil? || repository_id == 0 # Twirp converts nil values to 0
            next Twirp::Error.invalid_argument("must be non-empty", argument: "id")
          end

          Repositories::Public.resolve_tenant(id: repository_id)
        end

        # Public: Implementation of the CheckRepositoryActionsStatus Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Actions::Core::V1::CheckRepositoryActionsStatusRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Actions::Core::V1::CheckRepositoryActionsStatusResponse, or a Twirp::Error.
        def check_repository_actions_status(req, env)
          CheckRepositoryActionsStatus.call(req, env)
        end

        # Public: Implementation of the GetRepositoryOwners Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Actions::Core::V1::GetRepositoryOwnersRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Actions::Core::V1::GetRepositoryOwnersResponse, or a Twirp::Error.
        def get_repository_owners(req, env)
          GetRepositoryOwners.call(req, env)
        end

        # Public: Implementation of the GetCommitMessage Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Actions::Core::V1::GetCommitMessageRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Actions::Core::V1::GetCommitMessageResponse, or a Twirp::Error.
        def get_commit_message(req, env)
          GetCommitMessage.call(req, env)
        end

        # Public: Implementation of the RetireNamespace Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Actions::Core::V1::RetireNamespaceRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Actions::Core::V1::RetireNamespaceResponse, or a Twirp::Error.
        def retire_namespace(req, env)
          RetireNamespace.call(req, env)
        end

        # Public: Implementation of the FindRepositoriesByName Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Actions::Core::V1::FindRepositoriesByNameRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Actions::Core::V1::FindRepositoriesByNameResponse, or a Twirp::Error.
        def find_repositories_by_name(req, env)
          GetRepositoriesByName.call(req, env)
        end

        # Public: Implementation of the GetAdditionalWorkflows Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Actions::Core::V1::GetAdditionalWorkflowsRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Actions::Core::V1::GetAdditionalWorkflowsResponse, or a Twirp::Error.
        def get_additional_workflows(req, env)
          GetAdditionalWorkflows.call(req, env)
        end

        # Public: Implementation of the GetRepositoryEventDetails Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Actions::Core::V1::GetRepositoryEventDetailsRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Actions::Core::V1::GetRepositoryEventDetailsResponse, or a Twirp::Error.
        def get_repository_event_details(req, env)
          GetRepositoryEventDetails.call(req)
        end

        # Public: Implementation of the GetRepositoryOwnerId Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Actions::Core::V1::GetRepositoryOwnerIdRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Actions::Core::V1::GetRepositoryOwnerIdResponse, or a Twirp::Error.
        def get_repository_owner_id(req, env)
          GetRepositoryOwnerId.call(req, env)
        end
      end
    end
  end
end
