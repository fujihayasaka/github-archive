# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class IssueClosedStateReason < Platform::Enums::Base
      description "The possible state reasons of a closed issue."

      value "COMPLETED", "An issue that has been closed as completed", value: "completed"
      value "NOT_PLANNED", "An issue that has been closed as not planned", value: "not_planned"
      value "DUPLICATE", "An issue that has been closed as a duplicate", value: "duplicate"
    end
  end
end
