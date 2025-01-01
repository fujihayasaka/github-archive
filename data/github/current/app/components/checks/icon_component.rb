# typed: true
# frozen_string_literal: true

class Checks::IconComponent < ApplicationComponent
  include ChecksHelper

  CONCLUSION_ICONS_COLOR = {
    "timed_out"       => :danger,
    "failure"         => :danger,
    "success"         => :success,
    "action_required" => :danger,
    "skipped"         => :muted,
  }.freeze

  CONCLUSION_ICONS_CLASS = {
    "neutral"         => "neutral-check",
    "cancelled"       => "neutral-check",
    "stale"           => "neutral-check",
  }.freeze

  def initialize(conclusion:, status:, description: "")
    @conclusion = conclusion
    @status = status
    @description = description
  end

  private

  attr_reader :conclusion, :status, :description

  def icon
    check_run_state_icon(conclusion, status)
  end

  def color
    return :attention if conclusion.nil?
    CONCLUSION_ICONS_COLOR[conclusion]
  end

  def classes
    "selected-color-white #{CONCLUSION_ICONS_CLASS[conclusion]}".rstrip
  end

  def in_progress?
    status == "in_progress"
  end
end
