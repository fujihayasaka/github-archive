# typed: false
# frozen_string_literal: true

# Stores randomly generated one-time use recovery codes in the database to be
# verified later to decide if users can skip SAML/OIDC SSO.

module ExternalProviderRecoveryCodesMethods

  RECOVERY_CODE_USED_INSTRUMENTATION_KEY = "recovery_code_used"
  RECOVERY_CODE_FAILED_INSTRUMENTATION_KEY = "recovery_code_failed"
  RECOVERY_CODE_DOES_NOT_EXIST = "recovery code does not exist"
  RECOVERY_CODE_ALREADY_USED = "recovery code already used"

  # The total amount of recovery codes we send to the user
  # for storage. 16 is a nice amount. Smaller is inconvenient for
  # the user; bigger is kind of redundant.
  RECOVERY_CODE_TOTAL_COUNT = 16

  # The length of each recovery code we send to the user, in
  # decimal digits. E.g. length 10 could be displayd as XXXXX-XXXXX
  RECOVERY_CODE_LENGTH = 10

  # Generate the shared secret and recovery secret for skipping SAML/OIDC SSO.
  #
  # WARNING: This must be called **once** every time the User
  # enables SAML/OIDC.
  def generate_secrets!
    self.secret = SecureRandom.base64(32)
    generate_recovery! if self.recovery_secret.nil?
    true # Ensure the callback chain does not halt
  end

  # Generates the recovery secret for this account. This
  # secret is the base for generating the recovery keys.
  #
  # This function is called automatically every time a new shared
  # secret is generated: we have a set of recovery keys for each
  # secret.
  #
  # Additionally, this function can be called again if the user
  # runs out of recovery keys.
  #
  # Call #recovery_codes to get the current array
  # of recovery keys.
  def generate_recovery!
    self.recovery_secret = SecureRandom.base64(32)
    self.recovery_used_bitfield = 0
    self.recovery_codes_viewed = false
  end

  # Return an array of recovery codes.
  #
  # WARNING: This array must be given to the user **only once**,
  # when they activate dual factor authentication.
  #
  # By default we return 16 of these codes; they are one time use
  # only: once a code is used, it doesn't work anymore. They must
  # be used in consecutive order. Instruct the user to cross them
  # out as they are being used.
  #
  # If the user runs out of one-time keys, you can call
  # User#generate_two_factor_recovery! to generate 16 new keys.
  #
  # E.g.
  #
  #   ["01230123", "01230123", ...]
  #
  def recovery_codes(amount = RECOVERY_CODE_TOTAL_COUNT)
    amount.times.map { |n| recovery_code(n) }
  end

  # Recovery codes with a hyphen in the middle to make them easier to read.
  # E.g. "XXXXX-XXXXX"
  #
  # Returns an Array of Strings.
  def formatted_recovery_codes
    recovery_codes.map do |code|
      "#{code.slice(0, RECOVERY_CODE_LENGTH / 2)}-#{code.slice(RECOVERY_CODE_LENGTH / 2, RECOVERY_CODE_LENGTH / 2)}"
    end
  end

  # Return the first unused recovery code
  def first_unused_recovery_code
    n = 0
    until !recovery_code_used? n
      n += 1
    end
    recovery_code n
  end

  # Return the nth recovery key for dual-factor authentication
  #
  # Recovery keys are by default 8 numeric characters long,
  # returned as strings.
  def recovery_code(n)
    # salt is shared between SAML and OIDC
    mash = "#{recovery_secret}:#{n}:#{GitHub.saml_provider_salt}"
    OpenSSL::Digest::SHA1.hexdigest(mash)[0, RECOVERY_CODE_LENGTH] # rubocop:disable GitHub/InsecureHashAlgorithm
  end

  def recovery_code_used?(n)
    ((1 << n) & recovery_used_bitfield) != 0
  end

  def recovery_code_mark_used(n)
    bitfield = recovery_used_bitfield | (1 << n)
    update_attribute(:recovery_used_bitfield, bitfield)
  end

  # Public: verify the given recovery code and mark it used if verified.
  #
  # recovery_code - String either formatted with hyphens or not, representing
  #                 the recovery code to verify.
  #
  # Returns a boolean
  def verify_recovery_code!(recovery_code)
    idx = recovery_codes.index(deformatted_code(recovery_code))

    if idx.nil? || recovery_code_used?(idx)
      reason = idx.nil? ? RECOVERY_CODE_DOES_NOT_EXIST : RECOVERY_CODE_ALREADY_USED
      instrument_verify_recovery_code(name: RECOVERY_CODE_FAILED_INSTRUMENTATION_KEY, reason: reason)
      return false
    end

    recovery_code_mark_used(idx)
    instrument_verify_recovery_code(name: RECOVERY_CODE_USED_INSTRUMENTATION_KEY)
    true
  end

  private

  def deformatted_code(code)
    code && code.downcase.gsub(/[^a-z0-9]/, "")
  end

  def instrument_verify_recovery_code(name:, reason: nil)
    payload = {}
    if reason
      payload[:reason] = reason
    end
    target.instrument(name, payload)
  end
end
