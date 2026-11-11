# frozen_string_literal: true

class AccountStateMachine
  include Statesman::Machine
  include DenormalizeCurrentStateToModel

  state :inactive, initial: true
  state :active

  transition from: :inactive,       to: [:active]
  transition from: :active,         to: [:inactive]

  # All state changes should have an associated installation_id
  guard_transition do |_, _, metadata|
    metadata[:installation_id].present?
  end

  # Any transitions other than re-activations should have the same
  # installation_id as the previous transition
  guard_transition do |_, last_transition, metadata|
    next true if last_transition.nil?
    next true if last_transition.to_state.to_sym == :inactive

    last_transition.installation_id == metadata[:installation_id]
  end

  before_transition do |_, transition|
    transition.installation_id = transition.metadata.delete("installation_id")
  end
end
