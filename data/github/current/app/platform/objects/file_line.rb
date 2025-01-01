# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class FileLine < Platform::Objects::Base
      include GitHub::UTF8

      description "Represents a line of a file."

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

      field :html, String, description: "HTML formatted contents of this line.", null: false
      def html
        utf8(@object[:html]&.dup)
      end

      field :html_raw, Platform::Scalars::Base64String, description: "HTML formatted contents of this line. (Base-64 encoded)", null: false, method: :html

      field :number, Integer, description: "Line number for this line.", null: false
    end
  end
end
