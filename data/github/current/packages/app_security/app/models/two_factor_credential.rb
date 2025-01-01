# typed: true
# frozen_string_literal: true

class TwoFactorCredential < ApplicationRecord::Domain::Users
  include GitHub::Relay::GlobalIdentification
  include GitHub::BatchedScope
  include TwoFactorHelper

  belongs_to :user

  validates_presence_of :encrypted_recovery_secret, :recovery_used_bitfield, :user_id
  validate :only_one_per_user, on: :create

  encrypts :encrypted_recovery_secret

  after_create_commit  :instrument_creation
  after_destroy_commit :instrument_deletion
  after_update_commit  :instrument_update
  after_commit :set_or_unset_recovery_codes_not_viewed_notice
  after_commit :set_or_unset_staff_without_two_factor_notice
  after_commit :update_business_user_account_two_factor_status
  after_commit :update_low_recovery_codes_notice
  after_destroy :destroy_associated_registrations

  enum :login_preference, { sms_preferred: 1, app_preferred: 2, github_mobile_preferred: 3, webauthn_preferred: 4 }

  # Number of seconds the client and server timing can drift apart.  This
  # should prevent 2FA seemingly not working due to small timing differences.
  # This should be n*30 to accept codes from n intervals on either side of the
  # current time.
  ALLOWABLE_DRIFT = 90

  # What an OTP should look like
  OTP_REGEX = /\A\d{1,6}\z/

  # Number of seconds the user may retry entering the OTP before the login
  # process must restart.
  OTP_RETRY_WINDOW = 900

  # How long we store the timestamp of the last valid OTP (to prevent reuse)
  LAST_OTP_TTL = ALLOWABLE_DRIFT * 2

  def self.normalize_otp(otp)
    otp.to_s.downcase.gsub(/[^\h]/, "")
  end

  # Recovery codes with a hyphen in the middle to make them easier to read.
  #
  # Returns an Array of Strings.
  def formatted_recovery_codes
    GitHub::TwoFactorAuthentication.formatted_recovery_codes(self.encrypted_recovery_secret)
  end

  def find_recovery_code_index(recovery_code)
    GitHub::TwoFactorAuthentication.recovery_codes(self.encrypted_recovery_secret).index(recovery_code)
  end

  # Return the first unused recovery code
  def first_unused_recovery_code
    n = 0
    until !recovery_code_used? n
      n += 1
    end
    GitHub::TwoFactorAuthentication.recovery_code(self.encrypted_recovery_secret, n)
  end

  # Generates the two-factor recovery secret for this account. This
  # secret is the base for generating the recovery keys.
  #
  # This function is called automatically every time a new shared
  # secret is generated: we have a set of recovery keys for each
  # secret.
  #
  # Additionally, this function can be called again if the user
  # runs out of recovery keys.
  #
  # Call User#two_factor_recovery_codes to get the current array
  # of recovery keys.
  def generate_recovery_secret!
    self.encrypted_recovery_secret = self.class.generate_secret
    self.recovery_used_bitfield = 0
    self.recovery_codes_viewed = false
  end

  def self.generate_secret
    Base64.strict_encode64(OpenSSL::Random.random_bytes(32))
  end

  def recovery_code_used?(n)
    ((1 << n) & recovery_used_bitfield) != 0
  end

  def recovery_code_mark_used(n)
    bitfield = recovery_used_bitfield | (1 << n)
    AccountMailer.two_factor_recover(self.user, number_of_remaining_codes(bitfield)).deliver_later
    update_attribute(:recovery_used_bitfield, bitfield)
  end

  def recovery_codes_viewed!
    update_attribute(:recovery_codes_viewed, true)
  end

  def recovery_codes_downloaded!
    self.user&.instrument_two_factor_recovery_codes_downloaded
    update_attribute(:recovery_codes_last_downloaded_at, Time.now.utc)
  end

  def recovery_codes_printed!
    self.user&.instrument_two_factor_recovery_codes_printed
    update_attribute(:recovery_codes_last_printed_at, Time.now.utc)
  end

  # Determines if the two factor credential record is over a year old,
  # but the user has not saved their recovery codes after the first year since the record was created.
  def recovery_codes_unsaved_after_first_year
    T.must(created_at) < 1.year.ago &&
      (recovery_codes_last_downloaded_at.nil? || T.must(recovery_codes_last_downloaded_at) < T.must(created_at) + 1.year) &&
      (recovery_codes_last_printed_at.nil? || T.must(recovery_codes_last_printed_at) < T.must(created_at) + 1.year)
  end

  # It feels dangerous to add a method returning which codes are valid so let's
  # just return the count.
  def number_of_remaining_codes(bitfield = self.recovery_used_bitfield)
    GitHub::TwoFactorAuthentication::RECOVERY_CODE_TOTAL_COUNT - bitfield.to_s(2).count("1")
  end

  include Instrumentation::Model

  def event_prefix() :two_factor_authentication end

  def event_payload
    { user: self.user }
  end

  private

  # Instrument creating records.
  #
  # payload - Hash of custom payload data.
  #
  # Returns nothing.
  def instrument_creation(payload = {})
    instrument :enabled, payload
  end

  # Instrument deleting records.
  #
  # payload - Hash of custom payload data.
  #
  # Returns nothing.
  def instrument_deletion(payload = {})
    recovery_codes = GitHub::TwoFactorAuthentication.recovery_codes(self.encrypted_recovery_secret)
    instrument :disabled, payload.merge(
      recovery_codes: recovery_codes,
    )
  end

  def destroy_associated_registrations(payload = {})
    user&.sms_registrations&.destroy_all
    user&.totp_app_registration&.destroy
  end

  def instrument_update(payload = {})
    recovery_secret_changes = saved_change_to_encrypted_recovery_secret
    if recovery_secret_changes.present? && recovery_secret_changes.first != recovery_secret_changes.last
      instrument :recovery_codes_regenerated, payload
    end
  end

  def set_or_unset_recovery_codes_not_viewed_notice
    return if recovery_codes_viewed

    global_notice = GlobalNoticeNext.new(viewer: user)
    global_notice.set_notice(:two_factor_recovery_codes)
  end

  def update_low_recovery_codes_notice
    return if number_of_remaining_codes > 5

    global_notice = GlobalNoticeNext.new(viewer: user)
    global_notice.set_notice(:two_factor_low_recovery_codes)
  end

  def set_or_unset_staff_without_two_factor_notice
    # Skip reloading the user module unless they are actually staff
    return unless user&.has_staff_role?

    user&.reload.set_or_unset_staff_without_two_factor_notice
  end

  def update_business_user_account_two_factor_status
    return if GitHub.single_business_environment?

    BusinessUserAccount.where(user_id: user&.id).each do |bua|
      bua.update(two_factor_status: bua.two_factor_status_type(user))
    end
  end

  def only_one_per_user
    other_credentials = self.class.where(user_id: user&.id) - [self]
    return true if other_credentials.empty?
    self.errors.add(:uniq, "Only one TwoFactorCredential is allowed per user")
  end
end
