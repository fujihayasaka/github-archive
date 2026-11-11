# typed: strict
# frozen_string_literal: true

module Platform
  module Enums
    class IssueDependencyOrderField < Platform::Enums::Base
      description "Properties by which issue dependencies can be ordered."

      value "DEPENDENCY_ADDED_AT", "Order issue dependencies by time of when the dependency relationship was added", value: "dependency_added_at"
      value "CREATED_AT", "Order issue dependencies by the creation time of the dependent issue", value: "created_at"
    end
  end
end
