# typed: strict
# frozen_string_literal: true

module GH
  module Domain
    class Collection
      extend T::Generic
      extend T::Helpers
      extend Forwardable

      def_delegators :@collection_members, :size, :empty?

      include Enumerable

      Elem = type_member { { upper: BasicObject } }

      sig { params(members: T::Array[Elem]).void }
      def initialize(members)
        @collection_members = members
        @package = T.let(GitHub::DomainIsolation.current_domain, T.nilable(String))
      end

      sig do
        override.params(
          blk: T.proc.params(arg0: Elem).returns(BasicObject),
        ).returns(T::Array[Elem])
      end
      def each(&blk)
        collection_members.each { |member| yield member }
      end

      # Alias used by GraphQL
      sig { returns(T::Array[Elem]) }
      def to_ary
        self.to_a
      end

      protected

      sig { returns(T::Array[Elem]) }
      attr_reader :collection_members

      sig { returns(T.nilable(String)) }
      attr_reader :package
    end
  end
end
