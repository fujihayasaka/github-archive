# typed: true
# frozen_string_literal: true

module Platform
  # This makes a version of the schema which doesn't include any feature-flagged members.
  class SchemaDocsMask < SchemaVersionMask
    protected

    def hidden?(member, context)
      super || has_feature_flag?(member, context) || is_feature_flag_directive?(member, context) || is_for_mobile_only(member, context)
    end

    private

    # @return [Boolean] `true` if `member` is feature flagged _at all_
    def has_feature_flag?(member, context)
      member.respond_to?(:feature_flag) && !!member.feature_flag
    end

    def is_feature_flag_directive?(member, context)
      res = member.is_a?(Class) && member < GraphQL::Schema::Directive && member.graphql_name == "featureFlagged"
    end

    def is_for_mobile_only(member, context)
      member.respond_to?(:mobile_only) && !!member.mobile_only
    end
  end
end
