# typed: strict
# frozen_string_literal: true

require "gh/domain/collection"

module GH
  module Domain
    class Collection
      class Iterator
        extend T::Generic

        Elem = type_member { { upper: BasicObject } }

        sig do
          params(
            collection: GH::Domain::Collection[Elem],
            domain: GH::Domain::Base,
            domain_method: Symbol,
            kwargs: T.untyped
          ).void
        end
        def initialize(
          collection,
          domain,
          domain_method,
          **kwargs
        )
          @collection = collection
          @domain = domain
          @domain_method = domain_method
          @domain_kwargs = kwargs
        end

        sig { params(block: T.proc.params(arg0: GH::Domain::Collection[Elem]).void).void }
        def each_page(&block)
          collection.get_next_page(domain, domain_method, **domain_kwargs, &block)
        end

        private

        sig { returns(GH::Domain::Collection[Elem]) }
        attr_reader :collection

        sig { returns(GH::Domain::Base) }
        attr_reader :domain

        sig { returns(Symbol) }
        attr_reader :domain_method

        sig { returns(T::Hash[Symbol, T.anything]) }
        attr_reader :domain_kwargs
      end
    end
  end
end
