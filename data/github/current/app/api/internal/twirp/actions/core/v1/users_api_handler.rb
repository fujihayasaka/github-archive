# typed: true
# frozen_string_literal: true

require "monolith-twirp-actions-core"

module Api::Internal::Twirp::Actions
  module Core
    module V1
      # Handler for the MonolithTwirp::Actions::Core::V1::UsersAPIService
      class UsersAPIHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: ["launch"]
        handles_service MonolithTwirp::Actions::Core::V1::UsersAPIService

        # Get repositories accepts multiple repositories so we can't resolve one tenant for all of them
        exempt_from_tenant_context_requirement(
          only: %i[
            get_repositories
          ]
        )

        resolve_tenant_context only: %i[
          get_organization_owner
          is_visible_user
          should_pull_request_workflows_run_for_user
        ] do |req, _env|
          request = T.must(req)

          case req
          when MonolithTwirp::Actions::Core::V1::GetOrganizationOwnerRequest
            if request.id.nil? || request.id == 0
              next Twirp::Error.invalid_argument("must be non-empty", argument: "id")
            end

            Organization.find_by(id: request.id)&.resolve_tenant
          when MonolithTwirp::Actions::Core::V1::IsVisibleUserRequest
            if request.user_id.nil? || request.user_id == 0
              next Twirp::Error.invalid_argument("must be non-empty", argument: "user_id")
            end

            user = User.find_by(id: request.user_id)
            Business.enterprise_managed_business_for(resource: user)
          when MonolithTwirp::Actions::Core::V1::ShouldPullRequestWorkflowsRunForUserRequest
            begin
              repository_id = Platform::Helpers::NodeIdentification.from_global_id(request.repository.global_id).last
              Repositories::Public.resolve_tenant(id: repository_id)
            rescue Platform::Errors::NotFound
              Twirp::Error.invalid_argument("unable to resolve tenant", argument: "repository_id")
            end
          end
        end

        # Public: Implementation of the IsVisibleUser Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Actions::Core::V1::IsVisibleUserRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Actions::Core::V1::IsVisibleUserResponse, or a Twirp::Error.
        def is_visible_user(req, env)
          IsVisibleUser.call(req, env)
        end

        # Public: Implementation of the GetOrganizationOwner Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Actions::Core::V1::GetOrganizationOwnerRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Actions::Core::V1::GetOrganizationOwnerResponse, or a Twirp::Error.
        def get_organization_owner(req, env)
          GetOrganizationOwner.call(req, env)
        end

        # Public: Implementation of the GetRepositories Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Actions::Core::V1::GetRepositoriesRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Actions::Core::V1::GetRepositoriesResponse, or a Twirp::Error.
        def get_repositories(req, env)
          GetRepositories.call(req, env)
        end

        # Public: Implementation of the GetUserByLogin Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Actions::Core::V1::GetUserByLoginRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Actions::Core::V1::GetUserByLoginResponse, or a Twirp::Error.
        def get_user_by_login(req, env)
          GetUserByLogin.call(req)
        end

        # Public: Implementation of the ShouldPullRequestWorkflowsRunForUser Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Actions::Core::V1::ShouldPullRequestWorkflowsRunForUserRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Actions::Core::V1::ShouldPullRequestWorkflowsRunForUserResponse, or a Twirp::Error.
        def should_pull_request_workflows_run_for_user(req, env)
          ShouldPullRequestWorkflowsRunForUser.call(req)
        end
      end
    end
  end
end
