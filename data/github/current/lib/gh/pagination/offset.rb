# typed: strict
# frozen_string_literal: true

module GH
  module Pagination
    class Offset < GH::Pagination::Base
      DEFAULT_PER_PAGE = 30
      MAX_PER_PAGE = 100
      MAX_PER_PAGE_CEILING = 1_000

      sig { returns(Integer) }
      attr_accessor :page

      sig { returns(Integer) }
      attr_reader :per_page

      sig do
        params(
          per_page: T.nilable(T.any(Integer, String)),
          page: T.nilable(T.any(Integer, String)),
          default_per_page: Integer,
          max_per_page: Integer,
          validate: T::Boolean
        ).void
      end
      def initialize(
        per_page:,
        page:,
        default_per_page: DEFAULT_PER_PAGE,
        max_per_page: MAX_PER_PAGE,
        validate: true
      )
        unless validate
          @page = Integer(T.unsafe(page))
          @per_page = Integer(T.unsafe(per_page))
          return
        end

        max_per_page = MAX_PER_PAGE_CEILING if max_per_page > MAX_PER_PAGE_CEILING

        @page = T.let(begin
          [Integer(page || 0), 1].max
        rescue ArgumentError, TypeError
          1
        end, Integer)

        @per_page = T.let(begin
          Integer(per_page || default_per_page)
        rescue ArgumentError, TypeError
          default_per_page
        end, Integer)

        @per_page = default_per_page if @per_page <= 0
        @per_page = max_per_page if @per_page > max_per_page
      end
    end
  end
end
