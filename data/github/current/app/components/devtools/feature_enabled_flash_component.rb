# typed: true
# frozen_string_literal: true

class Devtools::FeatureEnabledFlashComponent < ApplicationComponent
  attr_reader :feature

  def initialize(feature:)
    @feature = feature
  end

  def flash_scheme
    feature.fully_enabled? ? :default : :warning
  end

  def title
    if feature.boolean_value == true
      "This feature is fully enabled"
    elsif feature.fully_disabled?
      "This feature is fully disabled"
    elsif enabled_methods.any?
      "This feature is #{enabled_methods.to_sentence}"
    end
  end

  def enabled_methods
    methods = []
    methods << "enabled for #{feature.percentage_of_actors_value}% of actors" if feature.percentage_of_actors_value > 0
    methods << "dark-shipped at #{feature.percentage_of_time_value}%" if feature.percentage_of_time_value > 0

    methods
  end

  def render?
    title.present?
  end
end
