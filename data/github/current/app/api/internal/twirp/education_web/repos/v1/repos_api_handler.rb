# typed: true
# frozen_string_literal: true

require "monolith-twirp-education_web-repos"

module Api::Internal::Twirp::EducationWeb
  module Repos
    module V1
      # Handler for the MonolithTwirp::EducationWeb::Repos::V1::ReposAPIService
      class ReposAPIHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: ["education_web"]
        handles_service MonolithTwirp::EducationWeb::Repos::V1::ReposAPIService
        connected_to_writing_for :get_repo_info

        # Public: Implementation of the GetRepoInfo Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::EducationWeb::Repos::V1::GetRepoInfoRequest.
        # env - The Twirp environment as a Hash.

        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::EducationWeb::Repos::V1::GetRepoInfoResponse.
        def get_repo_info(req, env)

          repo_ids = req.repo_ids.to_a
          Twirp::Error.invalid_argument("must be non-empty", argument: "repo_ids") unless repo_ids.present?

          repositories = ::Repositories::Public.load_repositories(repo_ids)

          results = repositories.map do |repo|
            {
             repository_id: repo.id,
             repository_url: repo.http_url,
             title: repo.full_name,
             active_issue_count: repo.issues.open_issues.without_pull_requests.count, # domain-isolation-query-violation:ignore:packages/issues (SELECT)
             star_count: repo.stargazer_count,
             fork_count: repo.forks_count,
             programming_language: repo.primary_language_name,
             topics: repo.topic_names,
             is_private: repo.private?,
             archived: repo.archived?,
             deleted: repo.deleted?,
             description: repo.description,
             discussion_count: repo.discussions.count,
             last_commit_at: repo.pushed_at.to_s
            }
          end

          { results: results }
        end
      end
    end
  end
end
