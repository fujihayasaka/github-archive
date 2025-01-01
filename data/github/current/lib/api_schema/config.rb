# typed: true
# frozen_string_literal: true

require "json_schema"

module ApiSchema
  class Config
    def self.with_ecmaregex(&block)
      previous_config = JsonSchema.configuration.validate_regex_with
      JsonSchema.configuration.validate_regex_with = :'ecma-re-validator'
      block.call
    ensure
      JsonSchema.configuration.validate_regex_with = previous_config
    end

    ROUTE_PATTERN_REPLACEMENTS = {
      "/branches/*"          => "/branches/:branch",
      "/commits/*"           => "/commits/:sha",
      "/labels/*"            => "/labels/:name",
      "/refs/*"              => "/refs/:ref",
    } unless const_defined?(:ROUTE_PATTERN_REPLACEMENTS)
  end
end
