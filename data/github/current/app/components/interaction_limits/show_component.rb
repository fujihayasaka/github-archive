# typed: true
# frozen_string_literal: true

class InteractionLimits::ShowComponent < ApplicationComponent
  def initialize(object:)
    @object = object
  end

  private

  attr_reader :object

  def render?
    return false unless GitHub.interaction_limits_enabled?
    object.present?
  end

  def organization?
    object.is_a?(Organization)
  end

  def repository?
    object.is_a?(Repository)
  end
end
