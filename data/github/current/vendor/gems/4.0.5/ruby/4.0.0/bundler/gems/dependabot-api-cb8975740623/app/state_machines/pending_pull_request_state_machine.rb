# frozen_string_literal: true

class PendingPullRequestStateMachine
  include Statesman::Machine
  include DenormalizeCurrentStateToModel

  state :pending, initial: true
  state :created
  state :abandoned

  transition from: :pending, to: %i(created abandoned)
end
