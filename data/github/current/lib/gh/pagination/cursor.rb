# typed: strict
# frozen_string_literal: true

module GH
  module Pagination
    class Cursor < GH::Pagination::Base
      extend T::Helpers

      sig { returns(T.nilable(String)) }
      attr_reader :after

      sig { returns(T.nilable(Integer)) }
      attr_reader :first

      sig { returns(T.nilable(String)) }
      attr_reader :before

      sig { returns(T.nilable(Integer)) }
      attr_reader :last

      sig { returns(T::Boolean) }
      attr_reader :disable_auth

      sig { params(after: T.nilable(String), before: T.nilable(String), first: T.nilable(Integer), last: T.nilable(Integer), disable_auth: T::Boolean).void }
      def initialize(after: nil, before: nil, first: nil, last: nil, disable_auth: false)
        @after = T.let(after, T.nilable(String))
        @before = T.let(before, T.nilable(String))
        @first = T.let(first, T.nilable(Integer))
        @last = T.let(last, T.nilable(Integer))
        @disable_auth = disable_auth
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def to_hash
        { after: after, before: before, first: first, last: last }
      end

      sig { params(hash: T.nilable(T::Hash[T.untyped, T.untyped])).returns(Cursor) }
      def self.from_hash(hash)
        hash = (hash || {}).slice(:before, :after, :first, :last)
        Cursor.new(after: hash[:after], before: hash[:before], first: hash[:first], last: hash[:last])
      end
    end
  end
end
