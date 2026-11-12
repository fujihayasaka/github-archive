# typed: strict
# frozen_string_literal: true

require_relative "pagination/iterator"

module OctoCore

  # A module that provides a way to iterate through pages of a collection of items.
  module Pagination
    extend T::Sig
    extend T::Helpers

    interface!

    Error = Class.new(StandardError)

    # A legacy pagination scheme that uses a page offset and item limit to paginate
    # through a collection like pages through a book.
    class Offset
      extend T::Sig

      include Pagination

      class BoundsExceededError < Error
        extend T::Sig

        sig { params(bound: Integer).void }
        def initialize(bound)
          @bound = bound
          super("requested pagination exceeds safe bounds")
        end

        sig { returns(Integer) }
        attr_reader :bound
      end

      PerPageBoundExceededError = Class.new(BoundsExceededError)
      UpperBoundExceededError = Class.new(BoundsExceededError)

      class Bounds
        extend T::Sig

        sig { returns(Bounds) }
        def self.default
          new
        end

        sig { params(max_record: Integer, max_per_page: Integer).void }
        def initialize(max_record: 40_000, max_per_page: 100)
          @max_record = max_record
          @max_per_page = max_per_page
        end

        sig { returns(Integer) }
        attr_reader :max_record

        sig { returns(Integer) }
        attr_reader :max_per_page

        sig { params(page: Integer, per_page: Integer).void }
        def validate!(page, per_page)
          raise UpperBoundExceededError.new(max_record) if page * per_page > max_record
          raise PerPageBoundExceededError.new(max_per_page) if per_page > max_per_page
        end
      end

      # Instantiate a new Offset pagination from nilable String request parameters using sensible defaults of
      # page 1 and 30 items per page.
      sig { params(page: T.nilable(String), per_page: T.nilable(String), bounds: Bounds, default_per_page: Integer).returns(Offset) }
      def self.from_request(page, per_page, bounds: Bounds.default, default_per_page: 30)
        page ||= 1
        per_page ||= default_per_page

        page = [page.to_i, 1].max

        per_page = per_page.to_i
        per_page = default_per_page if per_page < 1

        build(page:, per_page:, bounds:)
      end

      # Instantiate a new Offset pagination from the provided parameters, validating that they are within
      # the provided bounds.
      sig { params(page: Integer, per_page: Integer, bounds: Bounds).returns(Offset) }
      def self.build(page: 1, per_page: 30, bounds: Bounds.default)
        bounds.validate!(page, per_page)
        new(page: page, per_page: per_page)
      end

      # Prefer the `build` method to create instances of this class.
      private_class_method :new

      sig { params(page: Integer, per_page: Integer).void }
      def initialize(page: 1, per_page: 30)
        raise Error, "page must be greater than 0" if page < 1
        raise Error, "per_page must be greater than 0" if per_page < 1

        @page = page
        @per_page = per_page
      end

      sig { returns(Integer) }
      attr_reader :page

      sig { returns(Integer) }
      attr_reader :per_page

      sig { returns(Integer) }
      def offset
        (page - 1) * per_page
      end

      sig { params(scope: ::ActiveRecord::Relation).returns(::ActiveRecord::Relation) }
      def as_relation(scope)
        scope.limit(per_page).offset(offset)
      end

      sig { params(scope: ::ActiveRecord::Relation).returns(::ActiveRecord::Relation) }
      def as_subquery_relation(scope)
        subquery_scope = scope.reselect(:id).limit(per_page).offset(offset)
        subquery = subquery_scope.to_sql

        scope
          .unscoped
          .joins("INNER JOIN (#{subquery}) AS subquery ON `#{scope.table_name}`.id = subquery.id")
      end
    end
  end
end
