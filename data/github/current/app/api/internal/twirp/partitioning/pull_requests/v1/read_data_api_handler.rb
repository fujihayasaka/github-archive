# typed: true
# frozen_string_literal: true

require "monolith-twirp-partitioning-pull_requests"

module Api::Internal::Twirp::Partitioning
  module PullRequests
    module V1
      class ReadDataAPIHandler < Api::Internal::Twirp::Handler
        handles_service MonolithTwirp::Partitioning::PullRequests::V1::ReadDataAPIService
        allow_access_for :client, allowed_clients: ["partitioning"]

        DEFAULT_LIMIT = 20
        MAX_LIMIT = 500

        def filter_repositories_by_field(req, env)
          if req.project.empty?
            project = ["id"]
          else
            project = req.project.select { |f| Repository.column_names.include?(f) }
          end

          return Twirp::Error.invalid_argument("No valid fields.", argument: "project") if project.empty?

          limit = (req.limit.nil? || req.limit.zero?) ? DEFAULT_LIMIT : req.limit
          offset = req.offset
          filter_value = req.filter_value

          if req.scope == :SCOPE_IN_SAME_NETWORK_AS_SOURCE_ID
            if limit > MAX_LIMIT
              return Twirp::Error.invalid_argument("limit should not exceed #{MAX_LIMIT}. Please paginate your requests to return more records or talk to the PRs team if you need higher limits.", argument: "limit")
            end
            repos = Repository.where(source_id: filter_value).select(project).limit(limit).offset(offset)
          else
            # If the scope is allowed in the enum but not yet implemented, we return unimplemented error.
            # If the scope is unknown to the API module, client will get a 400 error because of invalid enum value.
            return Twirp::Error.unimplemented("Scope not yet implemented", meta: { argument: "scope", value: req.scope.to_s })
          end

          { data: repos.map(&:attributes) }
        end
      end
    end
  end
end
