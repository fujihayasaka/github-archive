# typed: strict
# frozen_string_literal: true

require "will_paginate/collection"
require "gh/domain/collection"

module GH
  module Domain
    class OffsetCollection < GH::Domain::Collection
      include GitHub::Memoizer

      Elem = type_member { { upper: BasicObject } }

      sig do
        params(
          members: T::Array[Elem],
          current_page: Integer,
          per_page: Integer,
          lazy_total_entries: T.nilable(T.proc.returns(Integer)),
        ).void
      end
      def initialize(members:, current_page:, per_page:, lazy_total_entries:)
        @current_page = current_page
        @per_page = per_page
        @lazy_total_entries = lazy_total_entries

        super(members)
      end

      # begin WillPaginate::Collection interface
      sig { returns(Integer) }
      attr_reader :current_page

      sig { returns(Integer) }
      attr_reader :per_page

      sig { returns(Integer) }
      def total_pages
        total_entries.zero? ? 1 : (total_entries / per_page.to_f).ceil
      end

      sig { returns(Integer) }
      memoize def total_entries
        GitHub::DomainIsolation.within_domain_of(@package) do
          @lazy_total_entries&.call
        end
      end
      # end WillPaginate::Collection interface

      # begin GitHub::SimplePagination interface
      sig { returns(T.nilable(Integer)) }
      def next_page
        current_page + 1 if total_entries > (current_page * per_page)
      end
      # end GitHub::SimplePagination interface

      sig { override.params(domain: GH::Domain::Base, domain_method: Symbol, domain_kwargs: T.untyped, block: T.proc.params(arg0: GH::Domain::Collection[Elem]).void).void }
      def get_next_page(domain, domain_method, **domain_kwargs, &block)
        pagination = T.cast(domain_kwargs.dig(:pagination), T.nilable(GH::Pagination::Offset))
        raise ArgumentError, "Domain method must accept pagination as kwarg to be iterable" unless pagination

        collection = self
        yield collection

        while collection.size == pagination.per_page do
          pagination.page += 1
          domain_kwargs.merge!(pagination: pagination)
          collection = T.cast(
            T.unsafe(domain).send(domain_method, **domain_kwargs), # rubocop:disable GitHub/AvoidObjectSendWithDynamicMethod:
            GH::Domain::OffsetCollection[Elem]
          )
          break if collection.empty?
          yield collection
        end
      end
    end
  end
end
