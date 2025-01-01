# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class DependabotUpdate < Platform::Objects::Base
      description "A Dependabot Update for a dependency in a repository"
      implements Interfaces::RepositoryNode
      minimum_accepted_scopes ["public_repo"]
      model_name "RepositoryDependencyUpdate"
      visibility :public

      def self.async_api_can_access?(permission, dependency_update)
        permission.async_can_read_dependabot_update?(dependency_update)
      end

      def self.async_viewer_can_see?(permission, dependency_update)
        permission.async_repo_and_org_owner(dependency_update).then do |repo, _org|
          repo.automated_security_updates_visible_to?(permission.viewer)
        end
      end

      field :error,
        Objects::DependabotUpdateError,
        "The error from a dependency update",
        null: true

      field :pull_request,
        Objects::PullRequest,
        "The associated pull request",
        null: true

      def error
        object if object.error_title.present?
      end

      def pull_request
        Loaders::ActiveRecord.load(::PullRequest, object.pull_request_id)
      end
    end
  end
end
