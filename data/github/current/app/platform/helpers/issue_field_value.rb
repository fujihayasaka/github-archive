# typed: strict
# frozen_string_literal: true

module Platform
  module Helpers
    class IssueFieldValue
      sig { params(permission: T.untyped, object: T.untyped).returns(::Promise[TrueClass]) }
      def self.async_api_can_access?(permission, object)
        # todo: issue fields - false if feature not enabled for owner org
        Promise.resolve(true)
      end

      sig { params(permission: T.untyped, object: T.untyped).returns(::Promise[TrueClass]) }
      def self.async_viewer_can_see?(permission, object)
        # todo: issue fields - false if feature not enabled for owner org
        Promise.resolve(true)
      end
    end
  end
end
