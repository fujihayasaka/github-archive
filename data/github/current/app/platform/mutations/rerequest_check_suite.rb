# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class RerequestCheckSuite < Platform::Mutations::Base
      include Platform::Helpers::GitHubAppValidation

      description "Rerequests an existing check suite."

      minimum_accepted_scopes ["public_repo"]

      limit_actors_to [:github_app]

      argument :repository_id, ID, "The Node ID of the repository.", required: true, loads: Objects::Repository, as: :repo
      argument :check_suite_id, ID, "The Node ID of the check suite.", required: true, loads: Objects::CheckSuite

      field :check_suite, Objects::CheckSuite, "The requested check suite.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, repo:, **inputs)
        permission.async_owner_if_org(repo).then do |org|
          permission.access_allowed?(:request_check_suite, resource: repo, current_repo: repo, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
        end
      end

      def resolve(check_suite:, repo:, **inputs)

        if repo.id != check_suite.repository_id # effectively, a 404
          raise Platform::Errors::NotFound.new("Could not resolve check run `#{inputs[:check_run_id]}` to repository `#{repo.global_relay_id}`")
        end

        unless allowed_to_modify_app?(app_id: check_suite.github_app_id) # effectively, a 403
          raise Platform::Errors::Forbidden.new("GitHub App `#{context[:integration].id}` can't manage check suite `#{check_suite.global_relay_id}`")
        end

        check_suite.rerequest(actor: context[:viewer])

        { check_suite: check_suite }
      rescue CheckSuite::NotRerequestableError
        raise Platform::Errors::Forbidden.new("This check suite is not rerequestable")
      end
    end
  end
end
