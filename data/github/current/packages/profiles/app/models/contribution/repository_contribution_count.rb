# typed: true
# frozen_string_literal: true

class Contribution::RepositoryContributionCount
  attr_reader :id
  attr_reader :count

  def initialize(id:, count:)
    @id = id
    @count = count
  end
end
