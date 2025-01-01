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
    end
  end
end
