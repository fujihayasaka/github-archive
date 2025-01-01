# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UnmarkFileAsViewed < Platform::Mutations::Base
      description "Unmark a pull request file as viewed"

      minimum_accepted_scopes ["public_repo"]

      argument :pull_request_id, ID, description: "The Node ID of the pull request.", required: true, loads: Objects::PullRequest
      argument :path, String, description: "The path of the file to mark as unviewed", required: true

      field :pull_request, Objects::PullRequest, "The updated pull request.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, pull_request:, **inputs)
        permission.async_repo_and_org_owner(pull_request).then do |repo, org|
          permission.access_allowed? :get_pull_request, repo: repo, current_org: org, resource: pull_request, allow_integrations: true, allow_user_via_granular_actor: true
        end
      end

      def resolve(pull_request:, **inputs)
        reviewed_file = context[:viewer].reviewed_files.for(pull_request).find_by(filepath: inputs[:path])

        if reviewed_file
          reviewed_file.destroy
        end

        { pull_request: pull_request }
      end
    end
  end
end
