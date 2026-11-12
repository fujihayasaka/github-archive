# frozen_string_literal: true

class UpdateConfigStateMachine
  include Statesman::Machine
  include DenormalizeCurrentStateToModel

  state :pending, initial: true
  state :rate_limited
  state :active
  state :deleted

  transition from: :pending,      to: :rate_limited
  transition from: :rate_limited, to: %i(active deleted)
  transition from: :active,       to: :deleted
  transition from: :deleted,      to: :rate_limited

  guard_transition(to: %i(active rate_limited)) do |config, _, metadata|
    next true if metadata[:validate] == false # for testing a transition, remove later

    !config.any_active_duplicates?
  end

  after_transition(to: :deleted) do |config, _|
    config.update_config_registries.destroy_all
    config.update!(next_enqueue_at: nil)
  end

  after_transition(to: :active) do |config, _|
    config.update_next_enqueue_at!
  end

  after_transition(to: :rate_limited) do |config, _|
    config.update_next_enqueue_at!
  end
end
