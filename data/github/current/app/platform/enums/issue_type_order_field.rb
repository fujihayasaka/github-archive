# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class IssueTypeOrderField < Platform::Enums::Base
      description "Properties by which issue type connections can be ordered."

      value "CREATED_AT", "Order issue types by creation time", value: "created_at"
      value "NAME", "Order issue types by name", value: "name"
    end
  end
end
