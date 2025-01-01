# typed: strict
# frozen_string_literal: true

module GH
  module Pagination
    class Cursor < GH::Pagination::Base
      extend T::Helpers

      sig { returns(T.nilable(String)) }
      attr_accessor :after

      sig { returns(T.nilable(Integer)) }
      attr_accessor :first

      sig { returns(T.nilable(String)) }
      attr_reader :before

      sig { returns(T.nilable(Integer)) }
      attr_reader :last

      sig { returns(T::Boolean) }
      attr_reader :disable_auth

      sig { returns(T.nilable(Integer)) }
      attr_reader :max_page_size

      sig { returns(T::Boolean) }
      attr_reader :disable_max_page_size_validation

      sig do params(
        after: T.nilable(String),
        before: T.nilable(String),
        first: T.nilable(Integer),
        last: T.nilable(Integer),
        max_page_size: T.nilable(Integer),
        disable_auth: T::Boolean,
        disable_max_page_size_validation: T::Boolean).void
      end
      def initialize(after: nil, before: nil, first: nil, last: nil, max_page_size: nil, disable_auth: false, disable_max_page_size_validation: false)
        @after = T.let(after, T.nilable(String))
        @before = T.let(before, T.nilable(String))
        @first = T.let(first, T.nilable(Integer))
        @last = T.let(last, T.nilable(Integer))
        @max_page_size = T.let(max_page_size, T.nilable(Integer))
        @disable_auth = disable_auth
        @disable_max_page_size_validation = T.let(disable_max_page_size_validation, T::Boolean)
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def to_hash
        { after: after, before: before, first: first, last: last, max_page_size: max_page_size, disable_max_page_size_validation: disable_max_page_size_validation }
      end

      sig { params(hash: T.nilable(T::Hash[T.untyped, T.untyped])).returns(Cursor) }
      def self.from_hash(hash)
        hash = (hash || {}).slice(:before, :after, :first, :last, :max_page_size)
        Cursor.new(
          after: hash[:after],
          before: hash[:before],
          first: hash[:first],
          last: hash[:last],
          max_page_size: hash[:max_page_size]
        )
      end
    end
  end
end
