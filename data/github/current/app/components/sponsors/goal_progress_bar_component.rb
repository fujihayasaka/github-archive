# typed: true
# frozen_string_literal: true

class Sponsors::GoalProgressBarComponent < ApplicationComponent
  # active_goal - SponsorsGoal object representing the sponsorable's active sponsorship goal
  def initialize(active_goal: nil)
    @active_goal = active_goal
  end

  private

  def render?
    @active_goal.present?
  end

  def goal_progress
    @active_goal.percent_complete.to_i
  end
end
