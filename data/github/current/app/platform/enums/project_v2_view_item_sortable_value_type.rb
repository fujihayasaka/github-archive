# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class ProjectV2ViewItemSortableValueType < Platform::Enums::Base
      description "The type of the value of a ProjectV2ViewItemSortableValue."
      required_capabilities [:mobile_only_schema_mask]

      value "STRING", "A string value", value: "string"
      value "FLOAT", "A float value", value: "float"
      value "INTEGER", "An integer value", value: "integer"
      value "NULL", "A null value", value: "null"
    end
  end
end
