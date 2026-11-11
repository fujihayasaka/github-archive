# frozen_string_literal: true

class PullRequestTransition < ApplicationRecord
  include Statesman::Adapters::ActiveRecordTransition

  belongs_to :pull_request, inverse_of: :pull_request_transitions
  has_one :update_job, inverse_of: :pull_request_transition

  validates :to_state, inclusion: { in: PullRequestStateMachine.states }
end
