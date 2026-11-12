# frozen_string_literal: true

class PendingPullRequestTransition < ApplicationRecord
  include Statesman::Adapters::ActiveRecordTransition

  belongs_to :pending_pull_request,
             inverse_of: :pending_pull_request_transitions

  validates :to_state, inclusion: { in: PendingPullRequestStateMachine.states }
end
