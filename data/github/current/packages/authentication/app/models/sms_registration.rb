# typed: true
# frozen_string_literal: true

class SmsRegistration < ApplicationRecord::Domain::Users
  include GitHub::Relay::GlobalIdentification
  include Instrumentation::Model

  belongs_to :user
  validates_presence_of :encrypted_otp_secret, :user_id, :sms_number
  validates :sms_number, uniqueness: { scope: :user_id }
  encrypts :encrypted_otp_secret
  validate :only_one_primary, if: :is_primary?, on: [:create]
  validate :max_two_registrations, on: [:create]
  validate :user_is_allowed_sms, on: [:create]
  validate :validate_sms_number_format, on: [:create, :update]

  after_create_commit  :instrument_creation
  after_destroy_commit :instrument_deletion
  after_update_commit  :instrument_update
  after_update_commit :check_low_availability_country

  validates_inclusion_of :sms_provider,
    in: GitHub::SMS.providers_for_env.map(&:provider_name).map(&:to_s),
    allow_nil: true

  def event_prefix() :two_factor_authentication end

  def event_payload
    { user: self.user }
  end

  # Public: Instrument when sms sent
  # only used for sending from primary number
  #
  # Returns nothing.
  def instrument_send_primary_sms(message_id:, provider_name:)
    return unless is_primary?
    instrument :send_primary_sms, message_id: message_id, provider: provider_name
  end

  # Public: Instrument when sms sent
  # only used for sending fallback
  #
  # Returns nothing.
  def instrument_send_fallback_sms(reason)
    return if is_primary?
    case reason
    when :reset
      instrument :password_reset_fallback_sms
    when :sign_in
      instrument :sign_in_fallback_sms
    when :checkup
      # instrumentation not required for :checkup
    else
      raise ArgumentError, "expected reason to be :reset or :sign_in"
    end
  end

  # Public: Check if user meets conditions for SmsLowAvailabilityCountryCheck banner
  # Low availability countries are countries where SMS delivery is less than 70% for either provider
  #
  # called by check_low_availability_country to set the banner
  # and two_factor_authentication_dependency#show_sms_low_availability_country_banner? before showing it
  #
  # Returns a boolean.
  def is_low_availability_country?
    country_code = GitHub::TwoFactorAuthentication.sms_country_code(sms_number)
    User::TwoFactorRegistrationsDependency::LOW_AVAILABILITY_COUNTRY_CODES.include?(country_code)
  end

  private

  # Instrument creating records.
  #
  # payload - Hash of custom payload data.
  #
  # Returns nothing.
  def instrument_creation(payload = {})
    # emit the fully hooked up audit event when we think the user isn't reconfiguring 2FA
    instrument :update_fallback, payload.merge(action: "create") unless created_with_2fa? || self.is_primary?

    instrument :add_factor, payload.merge(factor: "sms") if created_with_2fa? || self.is_primary?
  end

  def created_with_2fa?
    return unless self.user&.two_factor_credential.present?
    self.user&.two_factor_credential&.created_at&.between?(T.must(self.created_at) - 2.seconds, T.must(self.created_at) + 2.seconds)
  end

  # Instrument deleting records.
  #
  # payload - Hash of custom payload data.
  #
  # Returns nothing.
  def instrument_deletion(payload = {})
    # emit the fully hooked up audit event when we think the user isn't reconfiguring 2FA
    instrument :update_fallback, payload.merge(action: "delete") unless destroyed_with_2fa? || self.is_primary?

    instrument :remove_factor, payload.merge(factor: "sms") if destroyed_with_2fa? || self.is_primary?
  end

  def destroyed_with_2fa?
    return unless self.user&.two_factor_credential.present?
    self.user&.two_factor_credential&.destroyed?
  end

  def instrument_update(payload = {})
    if !self.is_primary? && saved_change_to_sms_number?
      instrument :update_fallback, payload.merge(action: "update")
    end

    # emits when a fallback SMS number has promoted to primary
    if self.is_primary? && saved_change_to_is_primary?
      instrument :add_factor, payload.merge(factor: "sms", reason: "promoted from fallback SMS")
    end

    if saved_change_to_sms_provider?
      audit_prefix = :user
      if Audit.context[:from]&.start_with?("stafftools")
        audit_prefix = :staff
      end

      instrument :switch_sms_provider, \
        prefix: audit_prefix,
        provider: sms_provider
    end
  end

  # Internal: validate that a User can only have one primary sms registration
  def only_one_primary
    return true unless self.user&.two_factor_primary_sms_registration?
    self.errors.add(:base, "Cannot have multiple primary sms registrations")
  end

  def max_two_registrations
    # the pending registration is not counted, so we need to check there are strictly <2
    return true if user&.sms_registrations&.count.to_i < 2
    self.errors.add(:base, "No more than two sms registrations are allowed")
  end

  def validate_sms_number_format
    if !self.sms_number || !GitHub::SMS.valid_number?(self.sms_number)
      errors.add(:sms_number, "is invalid")
    end
  end

  def check_low_availability_country
    return unless user&.show_sms_low_availability_country_banner?
    GlobalNoticeNext.new(viewer: user).set_notice(:sms_low_availability_country)
  end

  def user_is_allowed_sms
    return if user&.two_factor_sms_permitted?

    errors.add(:base, "SMS registration cannot be created for this user")
  end
end
