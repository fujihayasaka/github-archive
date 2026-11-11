# typed: strict
# frozen_string_literal: true

module Platform
  # This makes a version of the schema which doesn't include any feature-flagged members.
  class SchemaDocsMask < SchemaVersionMask
    FEDERATION_INTERNAL_TYPES = %w[_Service _Entity _Any].freeze
    FEDERATION_QUERY_FIELDS = %w[_service _entities].freeze

    protected

    sig { params(member: T.untyped, context: T.untyped).returns(T::Boolean) }
    def hidden?(member, context)
      super ||
        has_feature_flag?(member, context) ||
        is_feature_flag_directive?(member, context) ||
        is_for_required_capabilities(member, context) ||
        is_federation_internal_type?(member, context) ||
        is_federation_query_field?(member, context)
    end

    private

    # @return [Boolean] `true` if `member` is feature flagged _at all_
    sig { params(member: T.untyped, context: T.untyped).returns(T::Boolean) }
    def has_feature_flag?(member, context)
      member.respond_to?(:feature_flag) && !!member.feature_flag
    end

    sig { params(member: T.untyped, context: T.untyped).returns(T::Boolean) }
    def is_feature_flag_directive?(member, context)
      return false unless member.is_a?(Class)
      return false unless member < GraphQL::Schema::Directive
      return false unless member.respond_to?(:graphql_name)
      member.graphql_name == "featureFlagged"
    end

    sig { params(member: T.untyped, context: T.untyped).returns(T::Boolean) }
    def is_for_required_capabilities(member, context)
      member.respond_to?(:required_capabilities) &&
        member.required_capabilities.kind_of?(Array) &&
        member.required_capabilities.any?
    end

    sig { params(member: T.untyped, context: T.untyped).returns(T::Boolean) }
    def is_federation_internal_type?(member, context)
      return false unless member.respond_to?(:graphql_name)
      graphql_name = member.graphql_name
      FEDERATION_INTERNAL_TYPES.include?(graphql_name)
    end

    sig { params(member: T.untyped, context: T.untyped).returns(T::Boolean) }
    def is_federation_query_field?(member, context)
      return false unless member.is_a?(GraphQL::Schema::Field)
      return false unless member.respond_to?(:graphql_name)
      is_federation_field_name = FEDERATION_QUERY_FIELDS.include?(member.graphql_name)
      return false unless is_federation_field_name
      # We now need to verify it's specifically on the Query type.
      # We only hide federation fields on the Query type because other types may have fields with the same names that are not federation-related.
      return false unless member.respond_to?(:owner)
      return false unless member.owner.respond_to?(:graphql_name)
      return false unless context[:schema]
      member.owner.graphql_name == context[:schema].query.graphql_name
    end
  end
end
