# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class SupportContact < Platform::Objects::Base
      description "A support contact."
      mobile_only true

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true` because this object can't be accessed directly
      def self.async_api_can_access?(permission, push)
        true # rubocop:todo GitHub/GraphqlApiAuthorization
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true` because this object can't be accessed directly
      def self.async_viewer_can_see?(permission, push)
        true # rubocop:todo GitHub/GraphqlApiAuthorization
      end

      scopeless_tokens_as_minimum

      field :link, String, "The URL or email for the support contact", null: false

      field :link_type, Enums::SupportLinkType, "The type for the support contact link", null: false
    end
  end
end
