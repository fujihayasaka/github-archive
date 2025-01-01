# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class StreamingLog < Platform::Objects::Base
      description "Streaming log information for a check-run"
      visibility :internal

      # This object has no mapping to the database and has not specific permissions.
      # It can be accessed and viewed if the parent object can,
      # so we just return `true` in the following two methods

      def self.async_api_can_access?(permission, _object)
        # TODO write proper permissions before making this object public
        permission.hidden_from_public?(self)
      end

      def self.async_viewer_can_see?(permission, object)
        true # rubocop:todo GitHub/GraphqlApiAuthorization
      end

      scopeless_tokens_as_minimum

      field :url, Scalars::URI, "The URL of the log stream.", null: false
    end
  end
end
