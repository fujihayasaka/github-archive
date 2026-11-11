# typed: strict
# frozen_string_literal: true

module GH
  module Context
    # Frozen, no-op owner context returned when GH::Context is not enabled.
    #
    # Reads return safe defaults (nil/false). Writes raise to surface misuse,
    # consistent with NullContext's behavior for identity_context=.
    class NullOwnerContext < OwnerContext
      # Keep in sync with NullContext::MESSAGE (can't share the constant due to require order).
      MESSAGE = "GH::Context is not enabled! Please enable it by wrapping your code in GH::Context.enabled { ... }"

      # Raises — owner should not be set outside of an enabled context.
      sig { override.params(owner_id: T.nilable(Integer)).void }
      def id=(owner_id)
        raise MESSAGE
      end

      # Raises — unscoping should not be used outside of an enabled context.
      sig do
        override
          .type_parameters(:R)
          .params(block: T.proc.returns(T.type_parameter(:R)))
          .returns(T.type_parameter(:R))
      end
      def with_unscoped(&block)
        raise MESSAGE
      end
    end
  end
end
