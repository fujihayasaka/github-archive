# typed: strict
# frozen_string_literal: true

module Platform
  module Enums
    class WorkflowInputType < Platform::Enums::Base
      description "The possible types of inputs we support for dispatching a workflow."
      required_capabilities [:mobile_only_schema_mask]

      value "STRING",  "Any string value", value: "string"
      value "BOOLEAN", "A boolean/check box input", value: "boolean"
      value "CHOICE", "A single value from a list of defined choices", value: "choice"
      value "NUMBER", "A number input", value: "number"
      value "ENVIRONMENT", "A string input that is specfic to the repo environment", value: "environment"
    end
  end
end
