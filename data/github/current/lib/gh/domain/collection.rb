# typed: strict
# frozen_string_literal: true

require_relative "collection/iterator"

module GH
  module Domain
    class Collection
      extend T::Generic
      extend T::Helpers
      extend Forwardable

      def_delegators :@collection_members, :size, :empty?
      def_delegators :@iterator, :each_page

      include Enumerable

      Elem = type_member { { upper: BasicObject } }

      sig { params(members: T::Array[Elem]).void }
      def initialize(members)
        @collection_members = members
        @package = T.let(GitHub::DomainIsolation.current_domain, T.nilable(String))
        @iterator = T.let(nil, T.nilable(GH::Domain::Collection::Iterator[Elem]))
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

      sig { returns(GH::Domain::Collection::Iterator[Elem]) }
      def iterator
        raise "Collection is not iterable" unless @iterator
        @iterator
      end

      sig { params(domain: GH::Domain::Base, method: Symbol, kwargs: T.untyped).returns(GH::Domain::Collection[Elem]) }
      def iterable(domain, method, **kwargs)
        raise "Must include an argument for pagination" unless kwargs[:pagination]
        @iterator = GH::Domain::Collection::Iterator.new(self, domain, method, **kwargs)
        self
      end

      protected

      sig { params(domain: GH::Domain::Base, domain_method: Symbol, domain_kwargs: T.untyped, block: T.proc.params(arg0: GH::Domain::Collection[Elem]).void).void }
      def get_next_page(domain, domain_method, **domain_kwargs, &block)
        raise NotImplementedError, "Subclasses must implement #get_next_page"
      end

      sig { returns(T::Array[Elem]) }
      attr_reader :collection_members

      sig { returns(T.nilable(String)) }
      attr_reader :package
    end
  end
end
