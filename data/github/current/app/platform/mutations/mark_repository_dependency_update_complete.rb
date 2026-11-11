# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class MarkRepositoryDependencyUpdateComplete < Platform::Mutations::Base
      description "Updates the status of a RepositoryDependencyUpdate."

      visibility :internal
      minimum_accepted_scopes ["repo"]

      argument :database_id, Integer, "The database id of Repository Dependency Update that has completed.", required: true
      argument :pull_request_number, Integer, "The Pull Request number to associate with the update object.", required: true

      error_fields

      # This mutation should only be available to the Dependabot GitHub App
      def self.async_api_can_modify?(permission, **inputs)
        permission.viewer == GitHub.dependabot_github_app_bot
      end

      def resolve(database_id:, pull_request_number:, **inputs)
        repository_dependency_update = Loaders::ActiveRecord.load(::RepositoryDependencyUpdate, database_id).sync

        unless repository_dependency_update
          raise Errors::Unprocessable.new("Update ID '#{database_id}' does not exist.")
        end

        unless repository_dependency_update.repository
          raise Errors::Unprocessable.new("Repository ID '#{repository_dependency_update.repository_id}' does not exist.")
        end

        unless T.must(repository_dependency_update.repository).dependabot_installed?
          raise Errors::Unprocessable.new("The Dependabot app is not installed on Repository ID '#{repository_dependency_update.repository_id}'.")
        end

        pull_request = load_pull_request(repository_dependency_update.repository_id,
                                         pull_request_number)

        unless pull_request
          raise Errors::Unprocessable.new("Pull Request ##{pull_request_number} does not exist.")
        end

        # #mark_as_complete may be called on a completed update to associate it with a new pull
        # request without impacting its "complete" state or causing redundant metrics tracking.
        # We allow this mutation on a completed update to make it possible to change the pull
        # request associated with it, e.g., if Dependabot closed the previous pull request and
        # opened a new one.

        repository_dependency_update.mark_as_complete(pull_request: pull_request)

        {
          errors: Platform::UserErrors.mutation_errors_for_model(repository_dependency_update),
        }
      end

      private

      def load_pull_request(repository_id, number)
        Loaders::PullRequestByNumber.load(repository_id, number).sync # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      end
    end
  end
end
