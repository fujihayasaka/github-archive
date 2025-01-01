# typed: strict
# frozen_string_literal: true

# Internal: ActiveRecord class to persist the onboarding events.
class Onboarding::Event < ApplicationRecord::Domain::Users
  extend T::Sig

  include Instrumentation::Model
  self.table_name = :onboarding_events

  VALID_EVENTS = T.let(%w[
    enrolled_in_welcome_series
    welcomed_via_email
    answered_user_identification_questions
    enrolled_in_team_admin_onboarding_series
  ], T::Array[String])

  belongs_to :user
  validates_presence_of :user_id, :name
  validates :name, inclusion: { in: VALID_EVENTS }
  validates_uniqueness_of :name, scope: [:user_id], case_sensitive: false

  after_commit :instrument_name, on: :create

  private

  sig { returns(Symbol) }
  def event_prefix
    :onboarding
  end

  sig { returns(T::Hash[String, T.untyped]) }
  def event_payload
    {
      user: T.must(user).login,
      user_id: T.must(user).id,
      event: name,
    }
  end

  sig { void }
  def instrument_name
    instrument name
  end
end
