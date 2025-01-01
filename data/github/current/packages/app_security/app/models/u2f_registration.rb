# typed: true
# frozen_string_literal: true

class U2fRegistration < ApplicationRecord::Domain::Users

  include Instrumentation::Model
  include GitHub::Validations

  MAX_KEYS_PER_USER = 100
  UPDATE_THROTTLE = 1.hour

  belongs_to :user

  validate :validate_certificate
  validate :validate_public_key
  validate :validate_webauthn_attestation
  validate :validate_keys_per_user
  validate :validate_certificate_or_attestation_present
  validates :key_handle,               presence: true, length: { maximum: 1000 }
  validates :certificate,              length: { maximum: 10000 }
  validates :public_key,               presence: true, length: { maximum: 1000 }
  validates :nickname,                 presence: true, unicode3: true
  validates :nickname,                 uniqueness: { scope: :user_id, case_sensitive: false }, if: -> { T.unsafe(self).errors[:nickname].blank? }
  validates :counter,                  presence: true
  validates :webauthn_attestation,     length: { maximum: 65535 }
  validates :is_webauthn_registration, inclusion: { in: [true, false] }
  validates :is_passkey_registration, inclusion: { in: [true, false] }

  after_create_commit  :instrument_creation
  after_destroy_commit :instrument_deletion

  scope :passkeys, -> { where(is_passkey_registration: true) }
  scope :security_keys, -> { where(is_passkey_registration: false) }
  scope :user_verifying_security_keys, -> { where(is_passkey_registration: false, user_verifying: true) }

  has_many :trusted_device_client_registrations, dependent: :delete_all

  attr_accessor :page_view

  def track_webauthn_authenticated(reason, success, error, zero_counter)
    tags = [
      "result:#{success ? "success" : "failure"}",
      "action:webauthn_authenticated",
      "passkey:#{is_passkey_registration?}",
      "origin:#{reason}",
      "reason:#{error}",
    ]

    # Calls U2fRegistration.log_result() here
    self.class.log_result("webauthn_verify_registration_attempt", self.class.name, reason, success, error, self)
    tags = tags.concat(["zero_counter:#{zero_counter}"]) if !zero_counter.nil?
    GitHub.dogstats.increment("authentication.webauthn", tags: tags)
  end

  # Public: Log a webauthn verification attempt
  #
  # reason    - Webauthn attempt authentication scenario (sudo, 2fa, password_reset, etc)
  def self.log_result(type, code_namespace, reason, success, error, registration, data = nil)
    log_data = {
      "code.namespace" => code_namespace,
      :"gh.enduser.id" => GitHub.context[:actor_id],
      :"gh.request.id" => GitHub.context[:request_id],
      :"user_agent.original" => GitHub.context[:user_agent],
      :"gh.auth.result" => success ? "success" : "failure",
      :"gh.auth.result.message" => error,
      :"gh.auth.token_type" => "webauthn",
      :"gh.auth.webauthn.reason" => reason,
    }

    if registration.present?
      log_data[:"gh.auth.credential.user_id"] = registration.user_id,
      log_data[:"gh.auth.credential.key_handle"] = registration.key_handle
      log_data[:"gh.auth.credential.is_passkey"] = registration.is_passkey_registration
      log_data[:"gh.auth.credential.backup_eligibility"] = registration.backup_eligibility
      log_data[:"gh.auth.credential.backup_state"] = registration.backup_state
      log_data[:"gh.auth.credential.resident_key"] = registration.resident_key
      log_data[:"gh.auth.credential.user_verifying"] = registration.user_verifying
      log_data[:"gh.auth.credential.authenticator_type"] = registration.platform_authenticator ? "platform" : "cross-platform"
    end

    log_data.merge!(data) if data.present?

    GitHub.logger.info(type, log_data)
  end

  # Public: Check a signing response against a challenge.
  #
  # reason    - Webauthn attempt authentication scenario (sudo, 2fa, password_reset, etc)
  # origin    - The web origin of the client response.
  # challenge - A SignRequest challenge String.
  # response  - A WebAuthn::AuthenticatorAssertionResponse.
  #
  # Returns boolean.
  def webauthn_authenticated?(reason, origin, challenge, sign_response_hash, sign_response)
    unless GitHub.webauthn_allowed_origin?(origin)
      track_webauthn_authenticated(reason, false, :blocked_domain, nil)
      return false
    end

    # Signatures for legacy U2F registrations use the U2F app ID instead of the
    # RP ID. Our WebAuthn library doesn't support extensions, so we have to
    # compute this ourselves.
    rp_id = is_webauthn_registration ? GitHub.webauthn_rp_id : GitHub.u2f_app_id

    unless sign_response.valid?(Base64.urlsafe_decode64(challenge),
                           origin,
                           rp_id: rp_id,
                           public_key: raw_public_key,
                           sign_count: counter,
                          )
      track_webauthn_authenticated(reason, false, :invalid_sign_response, nil)
      return false
    end

    webauthn_authenticate_update_registration(reason, sign_response_hash, sign_response)
    track_webauthn_authenticated(reason, true, nil, sign_response.authenticator_data.sign_count.zero?)

    true
  end

  # updates registration metadata during authentication
  def webauthn_authenticate_update_registration(reason, sign_response_hash, sign_response)
    attributes = {}
    tags = ["passkey:#{is_passkey_registration?}",
      "reason:#{reason}",
    ]

    new_counter = sign_response.authenticator_data.sign_count
    new_backup_eligibility = sign_response.authenticator_data.flags.backup_eligibility
    new_backup_state = sign_response.authenticator_data.flags.backup_state
    new_user_verifying = sign_response.authenticator_data.flags.user_verified
    new_platform_authenticator = sign_response_hash["authenticator_attachment"] == "platform"

    attributes[:counter] = new_counter if counter != new_counter
    attributes[:backup_eligibility] = new_backup_eligibility if backup_eligibility != (new_backup_eligibility == 1)
    attributes[:backup_state] = new_backup_state if backup_state != (new_backup_state == 1)
    # We get different UV values depending on the request, but we want to use this column to keep track of if a credential can be user verifying
    # So we'll never update this value to UV:false if we've seen UV:true in the past
    attributes[:user_verifying] = new_user_verifying if !user_verifying && user_verifying != (new_user_verifying == 1)
    attributes[:platform_authenticator] = new_platform_authenticator if platform_authenticator != new_platform_authenticator
    # If no other attributes are being updated, we should still bump the record's last_used_at value once every hour on auth
    attributes[:last_used_at] = Time.now.utc if last_used_at.nil? || T.must(last_used_at) < (Time.now.utc - UPDATE_THROTTLE)

    if user_verifying && new_user_verifying == 0
      # if we would have cleared a true UV value
      GitHub.dogstats.increment("authentication.webauthn.uv_registration_performed_basic_auth",
        tags: ["passkey:#{is_passkey_registration?}", "reason:#{reason}", "platform_authenticator:#{platform_authenticator}"])
    end

    tags.concat(build_update_registration_tags(new_backup_eligibility, new_backup_state, new_user_verifying, new_platform_authenticator))
    tags.concat(["noop_update:#{ attributes.empty? }"])

    success = update(attributes)
    GitHub.dogstats.increment("authentication.webauthn.registration_updates", tags: tags.concat(["success:#{success}"]))
  end

  # check for passkey promote eligibility
  # this method is called during authentication to evaluate if a security key credential
  # can be flagged in the session cookie as eligible for passkey promotion
  #
  # also emits metrics so we can look at the breakdown of passkey eligible credentials during auth
  # additional context: https://github.com/github/github/blob/8be0154e70fa8ff291abb3e2aabdc53d3698be99/app/controllers/u2f_registrations_controller.rb#L113
  def is_passkey_eligible_on_auth?(reason, current_device_id, sudo_eligible = nil)
    eligible = if reason == :confirm
      # if a user is currently trying to manually promote an existing UV security key,
      !is_passkey_registration && user_verifying
    elsif reason == :login_2fa
      # or we have strong evidence that a UV security key is currently available
      # & because security key is eligible & user is about to see passkey promotion (trusted_device_available = nil or true)
      !!user&.authenticated_devices&.find_by(device_id: current_device_id)&.prompt_for_passkey_registration? &&
        !is_passkey_registration && user_verifying
    elsif reason == :sudo && sudo_eligible
      # or we have strong evidence that a UV security key is currently available & the user is performing sudo to register a passkey
      !is_passkey_registration && user_verifying
    else
      # otherwise we should only flag platform authenticators for upgrade since we can tell when they're available
      !is_passkey_registration && user_verifying && platform_authenticator
    end

    GitHub.dogstats.increment("webauthn.is_passkey_eligible", tags: [
      "reason:#{reason}",
      "is_passkey_registration:#{is_passkey_registration}",
      "user_verifying:#{user_verifying}",
      "resident_key:#{resident_key.nil? ? "nil" : resident_key}",
      "platform_authenticator:#{platform_authenticator}",
      "eligible:#{eligible}"
    ])

    eligible
  end

  # check if a credential is likely to be passkey promotable
  # additional context: https://github.com/github/github/blob/8be0154e70fa8ff291abb3e2aabdc53d3698be99/app/controllers/u2f_registrations_controller.rb#L113
  def is_uvpa?
    # passkeys are always uvpa, security keys can be uvpa
    user_verifying && platform_authenticator
  end

  def get_last_used_at
    last_used_at || updated_at
  end

  # used from u2f_registrations_controller to decide nicknaming behavior
  def nickname_type(upgrading)
    type = if upgrading
      "upgraded"
    elsif backup_eligibility
      "synced"
    elsif !platform_authenticator && (transports&.include?("usb") || transports&.include?("nfc"))
      "hardware"
    elsif platform_authenticator && !backup_eligibility
      "bound"
    else
      "unknown"
    end
  end

  # Because we can't use a cross-domain join
  def authenticated_devices_registered
    trusted_device_client_registrations.preload(:authenticated_device).map(&:authenticated_device)
  end

  # Public: The raw certificate bytes for this registration.
  #
  # Returns a String.
  def raw_public_key
    @raw_public_key ||= Base64.strict_decode64(public_key)
  end

  # Public: `webauthn` credential descriptor for this registration. This
  # represents the the credential passed to the browser, as described in
  # https://www.w3.org/TR/webauthn/#dom-publickeycredentialrequestoptions-allowcredentials
  #
  # Returns a Hash.
  def public_key_credential_descriptor
    descriptor = {
      type: "public-key",
      id: key_handle,
    }

    if is_passkey_registration? && !transports.nil? && !transports.empty?
      descriptor[:transports] = transports
    end

    descriptor
  end

  def linked_to_current_device?(current_device_id)
    current_device = user&.authenticated_devices&.find_by(device_id: current_device_id)
    return unless current_device
    trusted_device_client_registrations.where(authenticated_device_id: current_device.id).exists?
  end

  private

  # Private: Prefix for instrumentation events.
  #
  # Returns a Symbol.
  def event_prefix
    if is_passkey_registration?
      :passkey
    else
      :security_key
    end
  end

  # Private: Default metadata about the record
  #
  # Returns a Hash.
  def event_payload
    {
      user: user,
      credential_id: id,
      nickname: nickname,
      is_passkey_registration: is_passkey_registration?,
      is_uvpa: user_verifying? && platform_authenticator?,
      is_backup_eligible: backup_eligibility?,
    }
  end

  # Private: Instrument creating records.
  #
  # payload - Hash of custom payload data.
  #
  # Returns nothing.
  def instrument_creation(payload = {})
    GitHub.dogstats.increment "u2f_registration", tags: [
      "action:register",
      "recent_security_checkup:#{user&.recently_took_action_on_security_checkup?}",
      "related_global_notice:#{user&.two_factor_related_global_notice?}",
      "global_notice:#{user&.global_notice.name}",
      "passkey:#{is_passkey_registration?}",
      "page_view:#{page_view}"
    ]
    instrument :register, payload
  end

  # Private: Instrument deleting records.
  #
  # payload - Hash of custom payload data.
  #
  # Returns nothing.
  def instrument_deletion(payload = {})
    GitHub.dogstats.increment "u2f_registration", tags: ["action:remove", "passkey:#{is_passkey_registration?}"]
    instrument :remove, payload
  end

  # these tags are ugly, but they help make the metrics readable
  def build_update_registration_tags(new_backup_eligibility, new_backup_state, new_user_verifying, new_platform_authenticator)
    ["old_backup_eligibility:#{convert_for_tags(backup_eligibility)}",
      "new_backup_eligibility:#{new_backup_eligibility}",
      "old_backup_state:#{convert_for_tags(backup_state)}",
      "new_backup_state:#{new_backup_state}",
      "old_user_verifying:#{convert_for_tags(user_verifying)}",
      "new_user_verifying:#{new_user_verifying}",
      "old_platform_authenticator:#{convert_for_tags(platform_authenticator)}",
      "new_platform_authenticator:#{convert_for_tags(new_platform_authenticator)}"]
  end

  def convert_for_tags(val)
    return "nil" if val.nil?
    val ? 1 : 0
  end

  # Validate that the provided certificate can be parsed.
  #
  # Returns nothing.
  def validate_certificate
    return if certificate.nil?
    OpenSSL::X509::Certificate.new(Base64.strict_decode64(T.cast(certificate, String)))
  rescue OpenSSL::X509::CertificateError, ArgumentError
    errors.add(:certificate, "is invalid")
  end

  # Validate that the provided public key can be parsed.
  #
  # Returns nothing.
  def validate_public_key
    return if public_key.nil?

    begin
      raw = raw_public_key
    rescue ArgumentError
      return errors.add(:public_key, "is invalid")
    end

    # Detect uncompressed ECDSA points used by FIDO U2F. This is going away, as
    # we are migrating data to the COSE format used by WebAuthn.
    if raw_public_key.bytesize == 65 && raw_public_key.bytes.first == 0x04
      # We used to try to decode the public key with our old U2F library, but
      # this did nothing useful if the key had the proper length and leading
      # magic bit. So we don't have anything else to check.
      nil
    else
      begin
        COSE::Key.deserialize(raw_public_key)
      rescue COSE::Error => e
        GitHub.dogstats.increment("authentication.webauthn", tags: [
          "result:failure",
          "reason:#{e.class.name&.underscore}",
          "action:validate_public_key",
          "passkey:#{is_passkey_registration?}",
        ])
        errors.add(:public_key, "is invalid")
      end
    end
  end

  # Validate that the provided webauthn attestation can be parsed.
  #
  # Returns nothing.
  def validate_webauthn_attestation
    return unless public_key.nil?
    decoded = Base64.strict_decode64(webauthn_attestation)
    parsed = CBOR.decode(decoded)
    # Check that the attestation object has the required fields:
    # https://www.w3.org/TR/webauthn/#sctn-attestation
    %w[fmt attStmt authData].each do |key|
      if !parsed.has_key?(key)
        errors.add(:webauthn_attestation, "is missing key: #{key}")
        return
      end
    end
  rescue ArgumentError, EOFError
    errors.add(:webauthn_attestation, "is invalid")
  end

  # Check that the user hasn't registered too many keys.
  #
  # Returns nothing.
  def validate_keys_per_user
    max = new_record? ? MAX_KEYS_PER_USER - 1 : MAX_KEYS_PER_USER
    if user&.u2f_registrations&.security_keys&.count > max
      errors.add(:base, "users can only register #{MAX_KEYS_PER_USER} security keys")
    end
  end

  # Check that registration has a certificate or webauthn attestation, depending
  # on whether it's a webauthn registration:
  #
  # - Webauthn registration: has attestation
  # - U2F registration: has a certificate
  #
  # Returns nothing.
  def validate_certificate_or_attestation_present
    return if is_webauthn_registration && !webauthn_attestation.nil?
    return if !is_webauthn_registration && !certificate.nil?
    errors.add(:base, "security key registration proof (certificate or attestation) is missing")
  end
end
