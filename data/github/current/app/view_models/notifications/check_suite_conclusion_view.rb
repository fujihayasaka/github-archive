# typed: true
# frozen_string_literal: true

class Notifications::CheckSuiteConclusionView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  GREEN = "open".freeze
  RED = "closed".freeze
  NEUTRAL = "none".freeze
  RED_STATES = StatusCheckConfig::FAILURE_STATES + StatusCheckConfig::INCOMPLETE_STATES - [StatusCheckConfig::STALE]
  NEUTRAL_STATES = [StatusCheckConfig::NEUTRAL, StatusCheckConfig::SKIPPED, StatusCheckConfig::STALE, StatusCheckConfig::WAITING]

  def initialize(enum)
    @conclusion = enum
  end

  def adjective
    StatusCheckConfig.adjective_state(conclusion)
  end

  # We're just recycling existing class names here from SummaryView to get the
  # appropriate green, red, or neutral coloring for the notification icon.
  def summary_state
    if conclusion == StatusCheckConfig::SUCCESS
      GREEN
    elsif RED_STATES.include?(conclusion)
      RED
    else
      NEUTRAL
    end
  end

  def text_color
    case conclusion
    when StatusCheckConfig::SUCCESS
      "color-fg-success"
    when StatusCheckConfig::ACTION_REQUIRED, StatusCheckConfig::FAILURE, StatusCheckConfig::TIMED_OUT, StatusCheckConfig::STARTUP_FAILURE
      "color-fg-danger"
    when StatusCheckConfig::WAITING
      "hx_dot-fill-pending-icon"
    else
      "color-fg-muted"
    end
  end

  # Uses the same icons as we'd expect to see on the Checks pages.
  def icon
    config&.icon
  end

  def config
    StatusCheckConfig.for(conclusion)
  end

  private

  attr_reader :conclusion
end
