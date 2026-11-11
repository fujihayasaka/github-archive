# typed: true
# frozen_string_literal: true

class Sponsors::Dashboard::Goals::CompletedListComponent < ApplicationComponent
  include AvatarHelper

  SPONSORS_STACK_LIMIT = 5

  def initialize(completed_goals:)
    @completed_goals = completed_goals
  end

  private

  def render?
    @completed_goals.present? && logged_in?
  end

  def sponsors_to_render_for_goal(goal)
    goal
      .contributions
      .first(SPONSORS_STACK_LIMIT)
      .map(&:sponsor)
  end
end
