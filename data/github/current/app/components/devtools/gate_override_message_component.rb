# typed: true
# frozen_string_literal: true

class Devtools::GateOverrideMessageComponent < ApplicationComponent
  CONTEXT_TYPES = [:specific_actors, :groups, :actors, :dark_ship]
  DEFAULT_CONTEXT = :specific_actors

  attr_reader :feature, :context

  # Renders a Primer flash message explaining how this particular gate type
  # could be overridden by the feature's current rollout state.
  def initialize(feature:, context: DEFAULT_CONTEXT)
    @feature = feature
    @context = CONTEXT_TYPES.include?(context) ? context : DEFAULT_CONTEXT
  end

  def specific_actors?
    context == :specific_actors || context == :groups
  end

  def groups?
    context == :groups
  end

  def actors?
    context == :actors
  end

  def dark_ship?
    context == :dark_ship
  end

  # Is it possible for the specified gate type to have any effect given the current state of the feature?
  def gate_could_still_have_effect?
    return false if feature.boolean_value == true
    return true if actors? && feature.percentage_of_time_value < 100
    return true if dark_ship?
    false
  end

  def flash_scheme
    return :warning if gate_could_still_have_effect?
    :default
  end

  def message_title
    title = "This feature is fully enabled"

    return title if feature.boolean_value == true

    # The :actors gate type can specify if the feature is fully enabled via dark-ship, % of actors,
    # or both (this does happen sometimes). The other gate types only need to worry about the ones that can override.
    dark_ship_pct = feature.percentage_of_time_value.to_i
    actors_pct = feature.percentage_of_actors_value.to_i
    enabled_methods = []

    if (actors? && dark_ship_pct > 0) || (specific_actors? && dark_ship_pct == 100)
      enabled_methods << "dark-shipped to #{dark_ship_pct}%"
    end

    if (dark_ship? && actors_pct > 0) || (specific_actors? && actors_pct == 100)
      enabled_methods << "enabled for #{actors_pct}% of actors"
    end

    title = "This feature is #{enabled_methods.to_sentence}" if enabled_methods.any?

    title
  end

  def description
    message = if actors?
      "Changing the percentage of actors enabled"
    elsif dark_ship?
      "Changing the dark-ship rollout"
    else
      subject = groups? ? "groups" : "individual actors"
      "Adding or removing #{subject}"
    end

    message += if gate_could_still_have_effect?
      " may not have the intended effect."
    else
      " will have no effect."
    end
  end

  def render?
    # all gate types will be overridden if the feature is boolean-enabled
    return true if feature.on? && feature.percentage_of_time_value != 100.0

    return (feature.on? || feature.percentage_of_actors_value == 100) if specific_actors?
    return feature.percentage_of_time_value > 0 if actors?
    return feature.percentage_of_actors_value > 0 if dark_ship?

    false
  end
end
