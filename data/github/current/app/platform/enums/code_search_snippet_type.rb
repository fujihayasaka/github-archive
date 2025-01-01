# typed: true
# frozen_string_literal: true

require "blackbird-client"

module Platform
  module Enums
    # Exported type: sorbet/rbi/dsl/blackbird/query/v1/snippet_format.rbi
    class CodeSearchSnippetType < Platform::Enums::Base
      description "List of snippet format types"

      mobile_only true

      # Exported enum value: sorbet/rbi/dsl/blackbird/query/v1/snippet_format.rbi
      # Bind these directly to this enum to keep it as orthogonal as possible.
      # This should also fail the GraphQL schema validation if new enum values are added to the
      # underlying Blackbird enum and not regenerated (should be a good heads up for engineers on impact).
      ::Blackbird::Query::V1::SnippetFormat.constants.each do |constant|
        constant_name     = constant.to_s
        descriptive_value = constant_name.gsub("SNIPPET_FORMAT_", "").gsub("_", " ").capitalize

        value constant_name, "#{descriptive_value} format", value: ::Blackbird::Query::V1::SnippetFormat.const_get(constant)
      end
    end
  end
end
