# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class MilestoneOrderField < Platform::Enums::Base
      description "Properties by which milestone connections can be ordered."

      value "DUE_DATE", "Order milestones by when they are due.", value: "due_date"
      value "CREATED_AT", "Order milestones by when they were created.", value: "created_at"
      value "UPDATED_AT", "Order milestones by when they were last updated.", value: "updated_at"
      value "NUMBER", "Order milestones by their number.", value: "number"
      value "COMPLETED", "Order milestones by their completion status.", value: "completeness", visibility: :internal
      value "ISSUES", "Order milestones by the number of issues associated with them.", value: "count", visibility: :internal
      value "ALPHABETICAL", "Order milestones alphabetically by their title.", value: "title", visibility: :internal
    end
  end
end
