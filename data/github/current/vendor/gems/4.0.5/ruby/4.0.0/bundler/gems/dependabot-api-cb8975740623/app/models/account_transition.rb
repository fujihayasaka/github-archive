# frozen_string_literal: true

class AccountTransition < ApplicationRecord
  include Statesman::Adapters::ActiveRecordTransition

  belongs_to :account, inverse_of: :account_transitions

  validates :to_state, inclusion: { in: AccountStateMachine.states }

  scope :most_recent, -> { where(most_recent: true) }
  scope :active, -> { where(to_state: :active) }
end
