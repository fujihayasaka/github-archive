# typed: true
# frozen_string_literal: true

class TotpAppRegistration < ApplicationRecord::Domain::Users
  include GitHub::Relay::GlobalIdentification
  include Instrumentation::Model

  belongs_to :user
  validates_presence_of :encrypted_otp_secret, :user_id
  encrypts :encrypted_otp_secret

  validate :only_one_registration

  after_create_commit  :instrument_creation
  after_destroy_commit :instrument_deletion

  def event_prefix() :two_factor_authentication end

  def event_payload
    { user: self.user }
  end

  private

  def only_one_registration
    other_registrations = self.class.where(user_id: user&.id) - [self]
    return true if other_registrations.empty?
    self.errors.add(:base, "Only one totp app registration is allowed")
  end

  def instrument_creation(payload = {})
    instrument :add_factor, payload.merge(factor: "app")
  end

  def instrument_deletion(payload = {})
    instrument :remove_factor, payload.merge(factor: "app")
  end
end
