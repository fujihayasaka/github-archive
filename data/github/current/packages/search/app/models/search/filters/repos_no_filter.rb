# typed: strict
# frozen_string_literal: true

module Search
  module Filters
    class ReposNoFilter < ::Search::Filters::EnumeratedTermFilter
      extend T::Sig

      sig { params(opts: T::Hash[Symbol, T.untyped]).void }
      def initialize(opts = {})
        super(opts)

        @key_regex = T.let(opts[:key_regex], Regexp)
      end

      sig { returns(T.untyped) }
      def must_not
        # Restore original implementation as we don't need singular? in custom properties,
        # but we do need the custom #build implementation in this class
        build(bool_collection.must_not)
      end

      sig { params(values: T.nilable(T::Array[String])).returns(T.untyped) }
      def build(values)
        return if values.blank?

        values.filter_map { |v| no_clause(v) }
      end

      sig { returns(::Search::ParsedQuery::BoolCollection) }
      def bool_collection
        return T.must(@bool_collection) if defined? @bool_collection
        @bool_collection = T.let(::Search::ParsedQuery::BoolCollection.new(field), T.nilable(::Search::ParsedQuery::BoolCollection))

        qualifiers.filter { |key, _| key == :no }.each do |_, qualifier|
          qualifier.must&.each { |value| T.must(@bool_collection).must_not value }
          qualifier.must_not&.each { |value| T.must(@bool_collection).must value }
        end

        T.must(@bool_collection)
      end

      private

      sig { params(value: String).returns(T.nilable(T::Hash[T.untyped, T.untyped])) }
      def no_clause(value)
        return unless @key_regex.match(value)

        property_name = value.split(".").last
        { prefix: { field => "#{property_name}:" } }
      end
    end
  end
end
