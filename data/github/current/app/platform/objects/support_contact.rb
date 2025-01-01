# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class SupportContact < Platform::Objects::Base
      description "A support contact."
      mobile_only true

      # Returns `true` because this object can't be accessed directly but is instead only used
      # on pre-authorized objects, such as Platform::Objects::Query::Enterprise. In this one specific
      # use-case, the data returned is the same for all users, so we don't need to check permissions.
      def self.async_api_can_access?(permission, push)
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      # Returns `true` because this object can't be accessed directly but is instead only used
      # on pre-authorized objects, such as Platform::Objects::Query::Enterprise. In this one specific
      # use-case, the data returned is the same for all users, so we don't need to check permissions.
      def self.async_viewer_can_see?(permission, push)
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      scopeless_tokens_as_minimum

      field :link, String, "The URL or email for the support contact", null: false

      field :link_type, Enums::SupportLinkType, "The type for the support contact link", null: false
    end
  end
end
