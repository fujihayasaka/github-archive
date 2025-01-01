# typed: true
# frozen_string_literal: true

module Platform
  # This makes a version of the schema which doesn't include any feature-flagged members.
  class SchemaDocsMask < SchemaVersionMask
    protected

    def hidden?(member, context)
      super ||
        has_feature_flag?(member, context) ||
        is_feature_flag_directive?(member, context) ||
        is_for_required_capabilities(member, context)
    end

    private

    # @return [Boolean] `true` if `member` is feature flagged _at all_
    def has_feature_flag?(member, context)
      member.respond_to?(:feature_flag) && !!member.feature_flag
    end

    def is_feature_flag_directive?(member, context)
      res = member.is_a?(Class) && member < GraphQL::Schema::Directive && member.graphql_name == "featureFlagged"
    end

    def is_for_required_capabilities(member, context)
      member.respond_to?(:required_capabilities) &&
        member.required_capabilities.kind_of?(Array) &&
        member.required_capabilities.any?
    end
  end
end
