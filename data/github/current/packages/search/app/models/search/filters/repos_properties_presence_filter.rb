# typed: strict
# frozen_string_literal: true

module Search
  module Filters
    # Filter that handles both `has:` and `no:` qualifiers for repository properties.
    # - `has:props.{name}` generates a `must` prefix filter (repo MUST have the property set)
    # - `no:props.{name}` generates a `must_not` prefix filter (repo must NOT have the property set)
    #
    # The `property_regex` matches property names (e.g. PROPERTIES_PREFIXED_REGEX for custom properties).
    # The `field` is the ES index field to target (e.g. "custom_property_values.keyword").
    # This design allows future support for system_property_values by passing the appropriate field and regex.
    class ReposPropertiesPresenceFilter < ::Search::Filters::EnumeratedTermFilter
      sig { params(opts: T::Hash[Symbol, T.untyped]).void }
      def initialize(opts = {})
        super(opts)

        @property_regex = T.let(opts[:property_regex], Regexp)
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

        values.filter_map { |v| build_presence_clause(v) }
      end

      sig { returns(::Search::ParsedQuery::BoolCollection) }
      def bool_collection
        return T.must(@bool_collection) if defined? @bool_collection
        @bool_collection = T.let(::Search::ParsedQuery::BoolCollection.new(field), T.nilable(::Search::ParsedQuery::BoolCollection))

        # no: qualifier: repo must NOT have the property set
        qualifiers.filter { |key, _| key == :no }.each do |_, qualifier|
          qualifier.must&.each { |value| T.must(@bool_collection).must_not value }
          qualifier.must_not&.each { |value| T.must(@bool_collection).must value }
        end

        # has: qualifier: repo MUST have the property set
        qualifiers.filter { |key, _| key == :has }.each do |_, qualifier|
          qualifier.must&.each { |value| T.must(@bool_collection).must value }
          qualifier.must_not&.each { |value| T.must(@bool_collection).must_not value }
        end

        T.must(@bool_collection)
      end

      private

      sig { params(value: String).returns(T.nilable(T::Hash[T.untyped, T.untyped])) }
      def build_presence_clause(value)
        return unless @property_regex.match(value)

        property_name = value.split(".").last
        { prefix: { field => "#{property_name}:" } }
      end
    end
  end
end
