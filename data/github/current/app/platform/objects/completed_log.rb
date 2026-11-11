# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class CompletedLog < Platform::Objects::Base
      description "A completed log"
      visibility :internal

      # This object has no mapping to the database and has not specific permissions.
      # It can be accessed and viewed if the parent object can,
      # so we just return `true` in the following two methods

      def self.async_api_can_access?(permission, object)
        permission.hidden_from_public?(self) # Update this authorization if we ever go public with this object
      end

      def self.async_viewer_can_see?(permission, object)
        true # rubocop:todo GitHub/GraphqlApiAuthorization
      end

      scopeless_tokens_as_minimum

      field :url, Scalars::URI, "The URL where this completed log can be found.", null: false
      field :lines, Int, "The number of lines in the log.", null: false
    end
  end
end
