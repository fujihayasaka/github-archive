# typed: true
# frozen_string_literal: true

require "monolith-twirp-insights-core"

module Api::Internal::Twirp::Insights
  module Core
    module V1
      # Handler for the MonolithTwirp::Insights::Core::V1::RepositoryAPIService
      class RepositoryAPIHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: ["insights"]
        handles_service MonolithTwirp::Insights::Core::V1::RepositoryAPIService

        # Public: Implementation of the GetRepository Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Insights::Core::V1::GetRepositoryRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Insights::Core::V1::GetRepositoryResponse, or a Twirp::Error.
        def get_repository(req, env)
          GetRepositoryRecord.call(req, env)
        end

        # Public: Implementation of the GetRepositories Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Insights::Core::V1::GetRepositoriesRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Insights::Core::V1::GetRepositoriesResponse, or a Twirp::Error.
        def get_repositories(req, env)
          GitHub.dogstats.distribution_time("insights.monolith.repository_api.get_repositories.request.duration.ms") do
            GetRepositories.call(req, env)
          end
        end
      end
    end
  end
end
