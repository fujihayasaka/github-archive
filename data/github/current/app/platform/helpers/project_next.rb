# typed: true
# frozen_string_literal: true

module Platform
  module Helpers
    class ProjectNext
      DeprecationNotice = {
        start_date: Date.new(2022, 9, 26),
        reason: "The `ProjectNext` API is deprecated in favour of the more capable `ProjectV2` API.",
        superseded_by: "Follow the ProjectV2 guide at https://github.blog/changelog/2022-06-23-the-new-github-issues-june-23rd-update/, to find a suitable replacement.",
        owner: "lukewar",
      }

      def self.raise_missing_mutation_argument(argument, mutation_class)
        raise Errors::ArgumentError.new "Argument '#{argument}' on InputObject '#{mutation_class.name.demodulize}' is required. Expected type String"
      end

      def self.projects_next_graphql_api_disabled?(viewer, oauth_app)
        return false if Apps::Internal.capable?(:projects_next_graphql_api_disabled, app: oauth_app)
        viewer&.feature_enabled?(:projects_next_graphql_api_disabled)
      end

      def self.ensure_project_next_api_availability(viewer, oauth_app)
        raise Errors::NotFound.new "#{DeprecationNotice[:reason]} #{DeprecationNotice[:superseded_by]}" if projects_next_graphql_api_disabled?(viewer, oauth_app)
      end

      ProjectNextTypes = [
        Platform::Objects::ProjectNext,
        Platform::Objects::ProjectNextItem,
        Platform::Objects::ProjectNextField,
        Platform::Objects::ProjectNextGroupedViewItems,
        Platform::Objects::ProjectNextItemFieldGroup,
        Platform::Objects::ProjectNextItemFieldValue,
        Platform::Objects::ProjectNextItem,
        Platform::Objects::ProjectNextIterationFieldConfiguration,
        Platform::Objects::ProjectNextIterationFieldIteration,
        Platform::Objects::ProjectNextIterationField,
        Platform::Objects::ProjectNextSingleSelectFieldOption,
        Platform::Objects::ProjectNextSingleSelectField,
        Platform::Objects::ProjectNextViewItem
      ]

      def self.is_project_next_api_type?(type)
        ProjectNextTypes.include?(type)
      end
    end
  end
end
