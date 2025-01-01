# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    module Positions
      module Hydro
        # Serializes position objects for Hydro events by stripping internal metadata fields
        # that should not be propagated through our eventing system. Hydro events are consumed
        # by external services and clients, so we exclude implementation details like type
        # identifiers and commit OID context that are only relevant for internal processing.
        # The base_commit_oid and head_commit_oid are provided separately in the event payload
        # rather than being embedded within the position data itself.
        sig { params(value: T.untyped).returns(T::Hash[T.untyped, T.untyped]) }
        def self.serialize(value)
          case value
          when Positions then value.serialize.without("type", "base_commit_oid", "head_commit_oid")
          else value
          end
        end
      end
    end
  end
end
