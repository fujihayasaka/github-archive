# typed: strict
# frozen_string_literal: true

module Platform
  module Mutations
    class ArchivePullRequest < Platform::Mutations::Base
      docs_category :pulls
      description "Archive a pull request. Closes, locks, and marks the pull request as archived. " \
                  "Only repository admins can archive pull requests."

      minimum_accepted_scopes ["public_repo"]

      argument :pull_request_id, ID, "The Node ID of the pull request to archive.", required: true, loads: Objects::PullRequest

      field :pull_request, Objects::PullRequest, "The pull request that was archived.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      sig do
        params(
          permission: Platform::Authorization::Permission,
          pull_request: ::PullRequest,
          inputs: T.untyped
        ).returns(Promise[Promise[T::Boolean]])
      end
      def self.async_api_can_modify?(permission, pull_request:, **inputs)
        permission.async_repo_and_org_owner(pull_request).then do |repo, org|
          permission.access_allowed?(:update_pull_request, repo: repo, current_org: org, resource: pull_request, allow_integrations: true, allow_user_via_granular_actor: true)
        end
      end

      sig { params(pull_request: ::PullRequest).returns(Promise[{ pull_request: ::PullRequest }]) }
      def resolve(pull_request:)
        pull_request.async_repository.then do |repository|
          context[:permission].authorize_content(:pull_request, :update, repo: repository)

          check_database_resource_update_rate_limit!(resource: pull_request, current_user: context[:viewer])

          unless pull_request.archivable_by?(context[:viewer])
            raise Errors::Forbidden.new("#{context[:viewer].display_login} does not have permission to archive pull request #{pull_request.global_relay_id}.")
          end

          begin
            pull_request.archive!(context[:viewer], pull_request.issue)
          rescue PullRequest::Error => e
            raise Errors::Unprocessable.new(e.message)
          end

          { pull_request: pull_request }
        end
      end
    end
  end
end
