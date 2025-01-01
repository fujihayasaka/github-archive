# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class TextFileType < Platform::Objects::Base
      graphql_name "TextFileType"
      description "Represents a text file."


      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, _object)
        # To access this non Active Record object the caller already need to get permissions for a repo and a commit
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        # To access this non Active Record object the caller already need to get permissions for a repo and a commit
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      required_capabilities [:mobile_only_schema_mask]

      minimum_accepted_scopes ["repo"]

      implements Interfaces::TextFile

      field :content_html, Scalars::HTML, description: "Syntax highlighted html for the tree entry", null: true

      def content_html
        @object.async_colorized_lines.then do |colorized_lines|
          colorized_lines.join("\n").html_safe # rubocop:disable Rails/OutputSafety
        end
      end
    end
  end
end
