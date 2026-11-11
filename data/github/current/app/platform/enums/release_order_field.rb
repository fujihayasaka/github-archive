# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class ReleaseOrderField < Platform::Enums::Base
      description "Properties by which release connections can be ordered."

      value "CREATED_AT", "Order releases by creation time", value: "created_at"
      value "NAME", "Order releases alphabetically by name", value: "name"
    end
  end
end
