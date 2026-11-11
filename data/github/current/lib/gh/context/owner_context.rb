# typed: strict
# frozen_string_literal: true

module GH
  module Context
    # Mutable, request-scoped owner context for shard boundary detection.
    #
    # Tracks the current request's repository owner (User.id) and whether
    # owner scoping is intentionally bypassed (admin/search/explore routes).
    #
    # A fresh instance is created per `GH::Context.enabled` block, so owner
    # state is automatically scoped to the request/job lifecycle with no
    # manual reset required.
    #
    # Used by the owner-based shard boundary detection system to compare
    # query targets against the expected owner for the current request.
    class OwnerContext
      sig { void }
      def initialize
        @id = T.let(nil, T.nilable(Integer))
        @unscoped = T.let(false, T::Boolean)
      end

      # Returns the current owner_id, or nil if not set.
      sig { returns(T.nilable(Integer)) }
      attr_reader :id

      # Sets the current owner_id.
      sig { params(owner_id: T.nilable(Integer)).void }
      def id=(owner_id)
        @id = owner_id
      end

      # Returns true if owner scoping is currently disabled.
      sig { returns(T::Boolean) }
      def unscoped?
        @unscoped
      end

      # Temporarily disables owner scoping for the duration of the block.
      # Used for admin, search, explore, and other routes that intentionally
      # operate across owner boundaries.
      sig do
        type_parameters(:R)
          .params(block: T.proc.returns(T.type_parameter(:R)))
          .returns(T.type_parameter(:R))
      end
      def with_unscoped(&block)
        original = @unscoped
        @unscoped = true
        yield
      ensure
        @unscoped = T.must(original)
      end

      sig { returns(T::Hash[String, T.untyped]) }
      def logging_context
        {
          "gh.owner_set" => !id.nil?,
          "gh.owner.id" => id,
          "gh.owner.query_scoping" => unscoped? ? "disabled" : "enabled",
        }
      end

      sig { returns(T::Array[String]) }
      def metrics_tags
        [
          "owner_set:#{!id.nil?}",
          "owner_query_scoping:#{unscoped? ? "disabled" : "enabled"}",
        ]
      end
    end
  end
end
