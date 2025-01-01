# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class ProjectV2FieldOrderField < Platform::Enums::Base
      description "Properties by which project v2 field connections can be ordered."

      value "POSITION", "Order project v2 fields by position", value: "position"
      value "CREATED_AT", "Order project v2 fields by creation time", value: "created_at"
      value "NAME", "Order project v2 fields by name", value: "name"
    end
  end
end
