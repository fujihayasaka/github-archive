# typed: true
# frozen_string_literal: true

class Sponsors::Dashboard::Goals::FormComponent < ApplicationComponent

  def initialize(sponsors_listing:, goal: SponsorsGoal.new)
    @sponsors_listing = sponsors_listing
    @goal = goal
  end

  private

  attr_reader :sponsors_listing, :goal

  delegate :sponsorable_login, to: :sponsors_listing

  def render?
    return false unless logged_in?
    sponsors_listing.present?
  end

  def new_goal?
    !goal&.persisted?
  end

  def goal_type_label
    return "Goal:" unless goal

    if goal.total_sponsors_count?
      "Number of sponsors you're aiming for:"
    else
      "Monthly amount you're aiming for:"
    end
  end
end
