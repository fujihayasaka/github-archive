# typed: true
# frozen_string_literal: true

class Devtools::FeatureEnabledFlashComponent < ApplicationComponent
  attr_reader :feature

  def initialize(feature:)
    @feature = feature
  end

  def flash_scheme
    (feature.on? || feature.percentage_of_actors_value == 100) ? :default : :warning
  end

  def title
    # Check if _only_ the boolean gate is on
    if feature.on? && feature.percentage_of_actors_value < 100
      "This feature is fully enabled"
    elsif feature.off?
      "This feature is fully disabled"
    elsif enabled_methods.any?
      "This feature is #{enabled_methods.to_sentence}"
    end
  end

  def enabled_methods
    methods = []
    methods << "enabled for #{feature.percentage_of_actors_value.to_f}% of actors" if feature.percentage_of_actors_value > 0
    methods << "dark-shipped at #{feature.percentage_of_time_value.to_f}%" if feature.percentage_of_time_value > 0

    methods
  end

  def render?
    title.present?
  end
end
