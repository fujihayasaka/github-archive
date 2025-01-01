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
    end
  end
end
