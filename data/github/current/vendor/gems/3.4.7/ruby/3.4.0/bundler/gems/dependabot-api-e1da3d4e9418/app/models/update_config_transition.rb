# frozen_string_literal: true

class UpdateConfigTransition < ApplicationRecord
  include Statesman::Adapters::ActiveRecordTransition

  belongs_to :update_config, inverse_of: :update_config_transitions

  validates :to_state, inclusion: { in: UpdateConfigStateMachine.states }

  scope :most_recent, -> { where(most_recent: true) }
  scope :active, -> { where(to_state: %i(active rate_limited)) }
  scope :deleted, -> { where(to_state: :deleted) }
end
