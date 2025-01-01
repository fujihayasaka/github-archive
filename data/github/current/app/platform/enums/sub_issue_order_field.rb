# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class SubIssueOrderField < Platform::Enums::Base
      visibility :under_development
      description "Properties by which sub-issue issue connections can be ordered."

      # TODO: Right now, we always assume ordering by priority, but as we need different types of ordering, we should
      # begin to use this property
      value "PRIORITY", "Order sub-issues by the priority", value: "priority"
    end
  end
end
