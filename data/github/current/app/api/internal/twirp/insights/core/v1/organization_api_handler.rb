# typed: true
# frozen_string_literal: true

require "monolith-twirp-insights-core"

module Api::Internal::Twirp::Insights
  module Core
    module V1
      # Handler for the MonolithTwirp::Insights::Core::V1::OrganizationAPIService
      class OrganizationAPIHandler < Api::Internal::Twirp::Handler
        include GitHub::Tracing

        allow_access_for :client, allowed_clients: ["insights"]
        handles_service MonolithTwirp::Insights::Core::V1::OrganizationAPIService

        # Public: Implementation of the GetUsers Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Insights::Core::V1::GetUsersRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Insights::Core::V1::GetUsersResponse, or a Twirp::Error.
        trace_method :get_users
        def get_users(req, env)
          GitHub.dogstats.distribution_time("insights.monolith.organization_api.get_users.request.duration.ms") do
            GetOrganizationUsers.call(req, env)
          end
        end

        # Public: Implementation of the GetOrgInternalRepositories Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Insights::Core::V1::GetOrgInternalRepositoriesRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Insights::Core::V1::GetOrgInternalRepositoriesResponse, or a Twirp::Error.
        trace_method :get_org_internal_repositories
        def get_org_internal_repositories(req, env)
          GitHub.dogstats.distribution_time("insights.monolith.organization_api.get_org_internal_repositories.request.duration.ms") do
            GetOrgInternalRepositories.call(req, env)
          end
        end

        # Public: Implementation of the ListOrgPullRequests Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Insights::Core::V1::ListOrgPullRequestsRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Insights::Core::V1::ListOrgPullRequestsResponse, or a Twirp::Error.
        trace_method :list_org_pull_requests
        def list_org_pull_requests(req, env)
          GitHub.dogstats.distribution_time("insights.monolith.organization_api.list_org_pull_requests.request.duration.ms") do
            ListOrgPullRequests.call(req, env)
          end
        end

        # Public: Implementation of the GetRepositoryIdsForOrg Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Insights::Core::V1::GetRepositoryIdsForOrgRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Insights::Core::V1::GetRepositoryIdsForOrgResponse, or a Twirp::Error.
        trace_method :get_repository_ids_for_org
        def get_repository_ids_for_org(req, env)
          GitHub.dogstats.distribution_time("insights.monolith.organization_api.get_repository_ids_for_org.request.duration.ms") do
            GetRepositoryIdsForOrg.call(req, env)
          end
        end
      end
    end
  end
end
