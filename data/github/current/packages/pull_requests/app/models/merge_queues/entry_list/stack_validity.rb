# typed: strict
# frozen_string_literal: true

module MergeQueues
  class EntryList
    module StackValidity
      extend T::Helpers
      abstract!
      sealed!

      requires_ancestor { Object }

      sig { returns(OK) }
      def self.ok
        @ok ||= T.let(OK.new, T.nilable(OK))
      end

      sig { returns(NotFound) }
      def self.not_found
        @not_found ||= T.let(NotFound.new, T.nilable(NotFound))
      end

      class OK
        include StackValidity
      end

      class NotFound
        include StackValidity
      end

      class UnmergedParent < T::Struct
        include StackValidity
        const :entries, T::Array[Entry]
      end

      class NotContiguous < T::Struct
        include StackValidity
        const :entries, T::Array[Entry]
      end
    end
  end
end
