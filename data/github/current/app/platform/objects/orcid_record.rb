# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class OrcidRecord < Platform::Objects::Base
      description "An ORCID record associated with a GitHub account."

      required_capabilities [:mobile_only_schema_mask]

      scopeless_tokens_as_minimum

      def self.async_api_can_access?(permission, object)
        object.async_user.then do |user|
          permission.typed_can_access?("User", user)
        end
      end

      def self.async_viewer_can_see?(permission, object)
        object.async_user.then do |user|
          permission.typed_can_see?("User", user)
        end
      end

      field :identifier, String, null: false, description: "Unique, persistent identifier for academic researchers."

      field :profile_url, Scalars::URI, null: false, description: "URL for this user's profile on the ORCID site."
    end
  end
end
