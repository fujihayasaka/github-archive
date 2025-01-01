# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    module Positions
      module Rest
        # Serializes position objects for REST API responses by removing internal commit OID fields
        # that are not exposed in the public API. The base_commit_oid and head_commit_oid are
        # contextual data used internally but are provided separately in REST API responses
        # rather than being embedded within the position object itself.
        sig { params(value: T.untyped).returns(T::Hash[T.untyped, T.untyped]) }
        def self.serialize(value)
          case value
          when Positions then value.serialize.without("base_commit_oid", "head_commit_oid")
          else value
          end
        end
      end
    end
  end
end
