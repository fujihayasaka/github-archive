# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class MarkRepositoryDependencyUpdateErrored < Platform::Mutations::Base
      description "Updates the status of a RepositoryDependencyUpdate."

      visibility :internal
      minimum_accepted_scopes ["repo"]

      argument :database_id, Integer, "The database id of Repository Dependency Update that has errored.", required: true
      argument :error_title, String, "A title summarizing the error. Emoji supported.", required: true
      argument :error_body, String, "A description of the error(s). Markdown supported.", required: true
      argument :error_type, String, "The Dependabot update error type.", required: false

      error_fields

      # This mutation should only be available to the Dependabot GitHub App
      def self.async_api_can_modify?(permission, **inputs)
        permission.viewer == GitHub.dependabot_github_app_bot
      end

      def resolve(database_id:, error_title:, error_body:, **inputs)
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

        if repository_dependency_update.requested? || repository_dependency_update.timed_out?
          repository_dependency_update.mark_as_errored(title: error_title,
                                                       body: error_body,
                                                       type: inputs[:error_type])
        elsif repository_dependency_update.error?
          title_changed = repository_dependency_update.error_title != error_title
          body_changed = repository_dependency_update.error_body != error_body
          type_changed = repository_dependency_update.error_type != inputs[:error_type]

          if title_changed || body_changed || type_changed
            raise Errors::Unprocessable.new("Update ID '#{repository_dependency_update.id}' has already received an error.")
          end
        else
          raise Errors::Unprocessable.new("Update ID '#{repository_dependency_update.id}' cannot be marked as errored as it is currently '#{repository_dependency_update.state}'.")
        end

        {
          errors: Platform::UserErrors.mutation_errors_for_model(repository_dependency_update),
        }
      end
    end
  end
end
