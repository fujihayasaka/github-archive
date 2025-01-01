# typed: true
# frozen_string_literal: true

class StatusCheckRollup
  REQUIRED_DUCK_TYPE_METHODS = [
    :state,
    :state_changed_at,
    :sort_order,
    :duration_in_seconds,
  ]

  attr_reader :status_checks
  def initialize(status_checks:)
    @status_checks = status_checks
  end

  def state
    states = status_checks.map(&:state)
    StatusCheckRollup.rollup_state(states)
  end

  def self.state_is_pending(states)
    return true if states.empty?
    false
  end

  def self.state_is_failure(states)
    return true if states.any? { |state| (StatusCheckConfig::FAILURE_STATES + StatusCheckConfig::INCOMPLETE_STATES).include?(state) }
    false
  end

  def self.state_is_success(states)
    return true if states.all? { |state| StatusCheckConfig::SUCCESS_STATES.include?(state) }
    false
  end

  def updated_at
    # TODO: do we have a better name than state_changed_at?
    status_checks.map(&:state_changed_at).max
  end

  def self.rollup_state(states)
    return StatusCheckConfig::PENDING if StatusCheckRollup.state_is_pending(states)
    return StatusCheckConfig::FAILURE if StatusCheckRollup.state_is_failure(states)
    return StatusCheckConfig::SUCCESS if StatusCheckRollup.state_is_success(states)

    StatusCheckConfig::PENDING
  end

  # Short text description of the state
  def self.rollup_short_text(states, state)
    if state == StatusCheckConfig::FAILURE || state == StatusCheckConfig::SUCCESS
      successful_count = states.inject(0) { |sum, current_state| sum + ((StatusCheckConfig::SUCCESS_STATES).include?(current_state) ? 1 : 0) }

      return "#{successful_count} / #{states.count} checks OK"
    end
    nil
  end
end
