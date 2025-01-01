# typed: true
# frozen_string_literal: true

class Platform::Models::UserContribution
  attr_reader :user, :contributions_count

  def initialize(user, contributions_count)
    @user = user
    @contributions_count = contributions_count
  end
end
