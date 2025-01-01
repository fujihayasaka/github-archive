# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class IssueStateReason < Platform::Enums::Base

      description "The possible state reasons of an issue."

      value "REOPENED", "An issue that has been reopened", value: "reopened"
      value "NOT_PLANNED", "An issue that has been closed as not planned", value: "not_planned"
      value "COMPLETED", "An issue that has been closed as completed", value: "completed"
      value "DUPLICATE", "An issue that has been closed as a duplicate. To retrieve this value, set `(enableDuplicate: true)` when querying the stateReason field.", value: "duplicate"
    end
  end
end
