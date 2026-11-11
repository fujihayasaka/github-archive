# typed: true
# frozen_string_literal: true

# Public: Represents how many contributions of a given type a user has made on GitHub.
class Contribution::TypeCount
  attr_reader :contribution_type

  # Public: How many contributions of this type the user made.
  attr_accessor :count

  # Public: The percent of the user's total contributions that are of this type.
  attr_accessor :percentage

  # contribution_type - a String name describing the type of contribution, e.g., "Pull requests"
  def initialize(contribution_type:)
    @contribution_type = contribution_type
    @count = 0
    @percentage = 0
  end

  def platform_type_name
    "ContributionCount"
  end
end
