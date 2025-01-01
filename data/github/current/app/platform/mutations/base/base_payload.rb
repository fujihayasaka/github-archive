# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class Base < GraphQL::Schema::RelayClassicMutation
      class BasePayload < Platform::Objects::Base
        # Anyone who can run this mutation can see the payload
        def self.async_viewer_can_see?(*)
          true
        end

        def self.async_api_can_access?(*)
          true
        end
      end
    end
  end
end
