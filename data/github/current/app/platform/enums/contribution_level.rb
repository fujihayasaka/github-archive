# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class ContributionLevel < Platform::Enums::Base
      description "Varying levels of contributions from none to many."

      value "NONE", "No contributions occurred.", value: 0
      value "FIRST_QUARTILE", "Lowest 25% of days of contributions.", value: 1
      value "SECOND_QUARTILE", "Second lowest 25% of days of contributions. More contributions than the first quartile.", value: 2
      value "THIRD_QUARTILE", "Second highest 25% of days of contributions. More contributions than second quartile, less than the fourth quartile.", value: 3
      value "FOURTH_QUARTILE", "Highest 25% of days of contributions. More contributions than the third quartile.", value: 4
    end
  end
end
