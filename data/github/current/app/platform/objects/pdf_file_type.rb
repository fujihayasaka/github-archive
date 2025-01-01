# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class PdfFileType < Platform::Objects::Base
      graphql_name "PdfFileType"
      description "Represents a pdf file."


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

      mobile_only true

      minimum_accepted_scopes ["repo"]

      implements Interfaces::RawBlobUrl
    end
  end
end
