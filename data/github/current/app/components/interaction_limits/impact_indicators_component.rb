# typed: true
# frozen_string_literal: true

class InteractionLimits::ImpactIndicatorsComponent < ApplicationComponent

  DEFAULT_CLASSES = "d-flex flex-justify-start color-fg-muted text-small mt-1"

  def initialize(limit:, classes: DEFAULT_CLASSES, in_organization: false)
    @limit           = limit
    @classes         = classes
    @in_organization = in_organization
  end

  private

  attr_reader :limit, :classes, :in_organization

  def render?
    return false unless GitHub.interaction_limits_enabled?
    limit.present?
  end

  def icon_color(icon)
    icon == "check" ? :success : :danger
  end

  def users_icon
    limit == :sockpuppet_disallowed ? "check" : "x"
  end

  def contributors_icon
    limit == :collaborators_only ? "x" : "check"
  end
end
