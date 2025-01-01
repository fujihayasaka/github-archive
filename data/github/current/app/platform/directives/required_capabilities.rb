# typed: true
# frozen_string_literal: true
module Platform
  module Directives
    class RequiredCapabilities < GraphQL::Schema::Directive
      graphql_name "requiredCapabilities"
      argument :requiredCapabilities, [String], required: false
      locations OBJECT, SCALAR, ARGUMENT_DEFINITION, INTERFACE, INPUT_OBJECT, FIELD_DEFINITION, ENUM, ENUM_VALUE, UNION, INPUT_FIELD_DEFINITION
    end
  end
end
