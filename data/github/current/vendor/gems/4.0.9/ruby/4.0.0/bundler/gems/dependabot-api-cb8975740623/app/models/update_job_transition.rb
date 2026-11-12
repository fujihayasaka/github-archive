# frozen_string_literal: true

class UpdateJobTransition < ApplicationRecord
  include Statesman::Adapters::ActiveRecordTransition

  belongs_to :update_job, inverse_of: :update_job_transitions

  validates :to_state, inclusion: { in: UpdateJobStateMachine.states }
end
