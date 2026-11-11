# typed: true
# frozen_string_literal: true

require "monolith-twirp-mcpregistry-enrichment"

module Api::Internal::Twirp::Mcpregistry
  module Enrichment
    module V1
      # Handler for the MonolithTwirp::Mcpregistry::Enrichment::V1::EnrichmentAPIService
      class EnrichmentAPIHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: ["mcp_registry"]
        handles_service MonolithTwirp::Mcpregistry::Enrichment::V1::EnrichmentAPIService

        MAX_BATCH_SIZE = 50
        README_SIZE_LIMIT = 200.kilobytes

        # Public: Implementation of the GetRepositoryInfo Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Mcpregistry::Enrichment::V1::GetRepositoryInfoRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response data as a
        # MonolithTwirp::Mcpregistry::Enrichment::V1::GetRepositoryInfoResponse, or a Twirp::Error.
        def get_repository_info(req, env)
          owner_login = req.owner.to_s.strip
          repo_name = req.repo.to_s.strip

          return Twirp::Error.invalid_argument("owner must be present", argument: "owner") if owner_login.empty?
          return Twirp::Error.invalid_argument("repo must be present", argument: "repo") if repo_name.empty?

          repository = find_repository(owner_login, repo_name)
          return Twirp::Error.not_found("repository not found") unless repository

          { info: build_repository_info(repository) }
        end

        # Public: Implementation of the BatchGetRepositoryInfo Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Mcpregistry::Enrichment::V1::BatchGetRepositoryInfoRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response data as a
        # MonolithTwirp::Mcpregistry::Enrichment::V1::BatchGetRepositoryInfoResponse, or a Twirp::Error.
        def batch_get_repository_info(req, env)
          requests = req.requests.to_a
          return Twirp::Error.invalid_argument("requests must be non-empty", argument: "requests") if requests.empty?
          if requests.size > MAX_BATCH_SIZE
            return Twirp::Error.invalid_argument("requests must not exceed #{MAX_BATCH_SIZE} items", argument: "requests")
          end

          results = requests.map do |sub_req|
            owner_login = sub_req.owner.to_s.strip
            repo_name = sub_req.repo.to_s.strip

            if owner_login.empty? || repo_name.empty?
              { error_code: :ERROR_CODE_INTERNAL, error_message: "owner and repo must be present" }
            else
              repository = find_repository(owner_login, repo_name)
              if repository
                { info: build_repository_info(repository) }
              else
                { error_code: :ERROR_CODE_NOT_FOUND, error_message: "repository not found" }
              end
            end
          end

          { results: results }
        end

        # Public: Implementation of the GetRepositoryReadme Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Mcpregistry::Enrichment::V1::GetRepositoryReadmeRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response data as a
        # MonolithTwirp::Mcpregistry::Enrichment::V1::GetRepositoryReadmeResponse, or a Twirp::Error.
        def get_repository_readme(req, env)
          owner_login = req.owner.to_s.strip
          repo_name = req.repo.to_s.strip
          subfolder = req.subfolder.to_s.strip

          return Twirp::Error.invalid_argument("owner must be present", argument: "owner") if owner_login.empty?
          return Twirp::Error.invalid_argument("repo must be present", argument: "repo") if repo_name.empty?

          repository = find_repository(owner_login, repo_name)
          return Twirp::Error.not_found("repository not found") unless repository

          readme = fetch_readme(repository, subfolder)
          return { readme: nil } unless readme

          { readme: readme }
        end

        # Public: Implementation of the BatchGetRepositoryReadme Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Mcpregistry::Enrichment::V1::BatchGetRepositoryReadmeRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response data as a
        # MonolithTwirp::Mcpregistry::Enrichment::V1::BatchGetRepositoryReadmeResponse, or a Twirp::Error.
        def batch_get_repository_readme(req, env)
          requests = req.requests.to_a
          return Twirp::Error.invalid_argument("requests must be non-empty", argument: "requests") if requests.empty?
          if requests.size > MAX_BATCH_SIZE
            return Twirp::Error.invalid_argument("requests must not exceed #{MAX_BATCH_SIZE} items", argument: "requests")
          end

          results = requests.map do |sub_req|
            owner_login = sub_req.owner.to_s.strip
            repo_name = sub_req.repo.to_s.strip
            subfolder = sub_req.subfolder.to_s.strip

            if owner_login.empty? || repo_name.empty?
              { error_code: :ERROR_CODE_INTERNAL, error_message: "owner and repo must be present" }
            else
              repository = find_repository(owner_login, repo_name)
              if repository
                readme = fetch_readme(repository, subfolder)
                { readme: readme }
              else
                { error_code: :ERROR_CODE_NOT_FOUND, error_message: "repository not found" }
              end
            end
          end

          { results: results }
        end

        private

        def find_repository(owner_login, repo_name)
          Repository.nwo(owner_login, repo_name)
        end

        def build_repository_info(repository)
          owner = repository.owner
          primary_language = repository.primary_language
          license = repository.license

          {
            name: repository.name,
            name_with_owner: repository.name_with_owner,
            owner_avatar_url: owner&.primary_avatar_url.to_s,
            is_in_organization: owner.is_a?(Organization),
            stargazer_count: repository.stargazer_count,
            license: license&.name.to_s,
            primary_language: primary_language&.name.to_s,
            primary_language_color: primary_language&.color.to_s,
            topics: repository.topics.limit(10).pluck(:name),
            pushed_at: repository.pushed_at&.iso8601.to_s,
            homepage_url: repository.homepage.to_s,
            open_graph_image_url: repository.open_graph_image_url(nil).to_s,
            uses_custom_open_graph_image: repository.uses_custom_open_graph_image?,
            default_branch: repository.default_branch.to_s,
          }
        end

        def fetch_readme(repository, subfolder)
          readme_file = if subfolder.present?
            dir = Directory.new(repository, repository.default_branch, subfolder)
            dir.preferred_readme || repository.preferred_readme
          else
            repository.preferred_readme
          end
          return nil unless readme_file

          size = readme_file.size
          if size > README_SIZE_LIMIT
            { content: "", truncated: true }
          else
            { content: readme_file.data.to_s, truncated: false }
          end
        rescue GitRPC::InvalidFullOid
          nil
        end
      end
    end
  end
end
