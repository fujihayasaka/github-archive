# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ProjectV2SortByField < Platform::Objects::Base
      extend ProjectV2FieldAccessFilter

      description "Represents a sort by field and direction."

      scopeless_tokens_as_minimum

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, sort_by_field)
        unless GitHub.projects_new_enabled?
          raise Errors::Unprocessable::ProjectsNewDisabled.new
        end

        async_can_access?(permission, sort_by_field)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, sort_by_field)
        unless GitHub.projects_new_enabled?
          raise Errors::Unprocessable::ProjectsNewDisabled.new
        end

        async_can_access?(permission, sort_by_field)
      end

      field :field, Unions::ProjectV2FieldConfiguration, description: "The field by which items are sorted.", null: false
      field :direction, Platform::Enums::OrderDirection, description: "The direction of the sorting. Possible values are ASC and DESC.", null: false
    end
  end
end
