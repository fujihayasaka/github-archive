# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class TeamReviewAssignmentAlgorithm < Platform::Enums::Base
      description "The possible team review assignment algorithms"

      value "ROUND_ROBIN",  "Alternate reviews between each team member", value: "round_robin"
      value "LOAD_BALANCE", "Balance review load across the entire team", value: "load_balance"
    end
  end
end
