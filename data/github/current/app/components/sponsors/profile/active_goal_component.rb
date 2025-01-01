# typed: true
# frozen_string_literal: true

class Sponsors::Profile::ActiveGoalComponent < ApplicationComponent
  include AvatarHelper

  def initialize(sponsors_listing:, goal: nil, preview: false)
    @sponsors_listing = sponsors_listing
    @goal = goal
    @preview = preview
  end

  private

  attr_reader :sponsors_listing, :goal

  delegate :sponsorable_login, to: :sponsors_listing

  def render?
    return false unless sponsors_listing
    goal.present? || preview?
  end

  def preview?
    @preview
  end

  def goal_base_title
    "@#{sponsorable_login}'s goal is to"
  end

  def goal_title
    return "" if goal.blank?

    if goal.total_sponsors_count?
      "have #{goal.title}"
    else
      "earn #{goal.title}"
    end
  end

  def goal_description
    goal&.description.presence || "No description yet"
  end

  def target_value_preview_css_class
    return unless preview?
    "js-sponsors-goal-target-preview"
  end

  def description_preview_css_class
    return unless preview?
    "js-sponsors-goal-description-preview"
  end
end
