# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class DependabotUpdateError < Platform::Objects::Base
      description "An error produced from a Dependabot Update"
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

      field :title, String, "The title of the error", null: false, method: :error_title
      field :body, String, "The body of the error", null: false, method: :error_body
      field :error_type, String, "The error code", null: false

      def error_type
        object.error_type || ""
      end
    end
  end
end
