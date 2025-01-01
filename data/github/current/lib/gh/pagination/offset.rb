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

      # Initializes a new instance of the offset pagination class.
      #
      # @param per_page [Integer] The number of items per page.
      # @param page [Integer] The current page number.
      # @param default_per_page [Integer] The default number of items per page if not specified. Defaults to `DEFAULT_PER_PAGE`.
      # @param max_per_page [Integer] The maximum number of items allowed per page. Defaults to `MAX_PER_PAGE`.
      # @param validate [Boolean] Whether to validate and sanitize the input values. Defaults to `false`.
      #
      # If `validate` is `false`, the `page` and `per_page` values are directly converted to integers without additional checks.
      # If `validate` is `true`, the method ensures:
      # - `page` is at least 1, defaulting to 1 if invalid.
      # - `per_page` falls within the range of `default_per_page` and `max_per_page`, defaulting to `default_per_page` if invalid.
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
        validate: false
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

      # Creates a new instance of `GH::Pagination::Offset` from the given API pagination parameters.
      #
      # @param pagination [Hash] A hash containing pagination details.
      # @option pagination [Integer] `:per_page` The number of items per page.
      # @option pagination [Integer] `:page` The current page number.
      #
      # @return A new instance of `GH::Pagination::Offset` initialized with the provided parameters.
      sig do
        params(pagination: T::Hash[Symbol, Integer]).
        returns(GH::Pagination::Offset)
      end
      def self.from_api_pagination(pagination)
        GH::Pagination::Offset.new(
          per_page: pagination[:per_page],
          page: pagination[:page],
          default_per_page: DEFAULT_PER_PAGE,
          max_per_page: MAX_PER_PAGE,
          validate: true
        )
      end
    end
  end
end
