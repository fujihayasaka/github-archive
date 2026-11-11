# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class MobileSuggestedChange < Platform::Objects::Base
      description "Represents a suggested change in a pull request review comment body."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, object)
        # object is #<Platform::Models::MobileSuggestedChange @path="README.txt", @suggestion="four\nfive"
        # the object doesn't have any connection at this point to a repo, org, or pull to scope permission. It's derived from the contents of a review comment.
        true # rubocop:todo GitHub/GraphqlApiAuthorization
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        # object is #<Platform::Models::MobileSuggestedChange @path="README.txt", @suggestion="four\nfive"
        # the object doesn't have any connection at this point to a repo, org, or pull to scope permission. It's derived from the contents of a review comment.
        true # rubocop:todo GitHub/GraphqlApiAuthorization
      end

      scopeless_tokens_as_minimum
      required_capabilities [:mobile_only_schema_mask]

      field :path, String, "The file the comments were made on.", null: true
      field :suggestion, [String], "The contents of the code suggestion, e.g. ['def new_method']", null: true

      def self.load_from_global_id(id)
        Models::MobileSuggestedChange.load_from_global_id(id)
      end
    end
  end
end
