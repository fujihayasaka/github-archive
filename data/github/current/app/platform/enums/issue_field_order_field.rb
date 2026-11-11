# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class IssueFieldOrderField < Platform::Enums::Base
      description "Properties by which issue field connections can be ordered."

      value "CREATED_AT", "Order issue fields by creation time", value: "created_at"
      value "NAME", "Order issue fields by name", value: "name"
    end
  end
end
