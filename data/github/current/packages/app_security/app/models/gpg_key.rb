# typed: true
# frozen_string_literal: true

class GpgKey < ApplicationRecord::Domain::Users
  extend T::Helpers

  belongs_to :user
  belongs_to :primary_key, class_name: "GpgKey"
  # rubocop:todo Rails/InverseOf
  has_many :subkeys, class_name: "GpgKey", foreign_key: :primary_key_id, dependent: :destroy
  # rubocop:enable Rails/InverseOf
  has_many :emails, class_name: "GpgKeyEmail", dependent: :destroy
  has_many :verified_user_emails, through: :emails
  has_many :user_emails, through: :emails

  scope :primary_keys, lambda { where("primary_key_id IS NULL") }
  scope :with_subkeys, lambda { includes(:subkeys) }
  scope :with_emails,  lambda {
    if GitHub.email_verification_enabled?
      includes(:verified_user_emails, primary_key: [:verified_user_emails])
    else
      includes(:user_emails, primary_key: [:user_emails])
    end
  }

  validate :raw_key_utf8_safe

  validates(:user_id,
    presence: true,
  )

  validates(:key_id,
    presence: true,
    uniqueness: { scope: :user_id, message: "already exists" },
    length: { is: 8 },
  )

  validates(:public_key,
    presence: true,
    uniqueness: { scope: :user_id, message: "already exists" },
    length: { maximum: 100.kilobytes },
  )

  include GitHub::Validations
  validates(:name,
    length: { maximum: 100 },
    unicode3: true,
    allow_blank: true
  )

  after_destroy_commit :instrument_deletion

  # Create a GpgKey, it's GpgKeyEmails, and subkeys from an armored GPG public
  # key.
  #
  # public_key - An ASCII armored GPG public key String.
  #
  # Returns a GpgKey instance.
  def self.create_from_armored_public_key(public_key, name: nil, accept_revoked_keys: false)
    decoded = decode_armored_public_key(public_key)
    return decoded if decoded["primary_key"].nil?

    primary_key = decoded["primary_key"]

    # GPG Verify will return revoked keys with two bools in the hash, "revoked" and "compromised"
    # We will reject any primary key that has been revoked or compromised.
    # If accept_revoked_keys is true, then we will reject any primary key that has
    # been revoked due to being compromised.
    if primary_key["revoked"] && (!accept_revoked_keys || primary_key["compromised"])
      key = T.let(all.new, GpgKey)
      key.errors.add(:base, "The key was not added because the primary key is " + (accept_revoked_keys ? "compromised" : "revoked"))
      return key
    end

    transaction do
      key = T.let(all.new(
        name: name,
        raw_key: public_key,
        public_key: primary_key["raw_data"],
        key_id: primary_key["fingerprint"].byteslice(-8..-1),
        expires_at: expires_at_value(primary_key["expiration_at"]),
        can_sign: primary_key["usage"]["signing"],
        can_encrypt_comms: primary_key["usage"]["encrypt_communications"],
        can_encrypt_storage: primary_key["usage"]["encrypt_storage"],
        can_certify: primary_key["usage"]["certification"],
        revoked: primary_key["revoked"] || false,
      ), GpgKey)

      # Deduplicate subkeys, taking the most recently created
      subkeys = decoded["subkeys"] || []
      by_fp = subkeys.group_by { |sk| sk["fingerprint"] }
      subkeys = by_fp.values.map do |sks|
        sks.sort_by! { |sk| expires_at_value(sk["created_at"]) }
        sks.last
      end

      # check subkeys for DB uniqueness
      subkey_ids = subkeys.map { |sk| sk["fingerprint"].byteslice(-8..-1) }
      existing_subkeys = GpgKey.where(user_id: key.user_id, key_id: subkey_ids)
      if existing_subkeys.any?
        ids = existing_subkeys.map(&:hex_key_id).join(", ")
        key.errors.add(:base, "The key was not added because one or more subkeys already exist: #{ids}")
      end

      # key.valid? clears existing errors and reruns validators, so check key.errors instead
      if key.errors.empty? && key.save
        key.create_emails(decoded["user_ids"])
        key.create_subkeys(subkeys, accept_revoked_keys: accept_revoked_keys)
        key.instrument_creation
      end

      decoded["bad_subkeys"]&.each do |subkey|
        GitHub.logger.info("GpgKey: Subkey #{subkey["subkey_id"]} validation error: #{subkey["error"]}")
        bad_subkey = key.subkeys.build(key_id: subkey["subkey_id"])
        bad_subkey.errors.add(:base, "Subkey #{subkey["subkey_id"]} was not added because it is not valid")
      end

      key
    end
  end

  # Decodes a GpgKey, it's GpgKeyEmails, and subkeys from an armored GPG public
  # key.
  #
  # public_key - An ASCII armored GPG public key String.
  #
  # Returns a decoded key
  def self.decode_armored_public_key(public_key)
    begin
      public_key = public_key.gsub(/^ +/, "").strip
      GitHub.gpg.decode_public_keys([public_key]).first
    rescue GpgVerify::Error => e
      key = all.new
      key.errors.add(:base, e.user_message)
      key
    end
  end

  # Combine the keys into a single, armored keychain.
  #
  # Returns an ASCII armored String.
  def self.keychain
    missing_raw_key = []
    decode_error = []
    decoded = []

    find_each do |key|
      if key.raw_key.blank?
        missing_raw_key << key.hex_key_id
        next
      end

      begin
        decoded << PgpArmor.decode(key.raw_key).last
      rescue PgpArmor::ArmorError
        decode_error << key.hex_key_id
      end
    end

    headers = {}

    if missing_raw_key.none? && decode_error.none? && decoded.none?
      headers["Note"] = "This user hasn't uploaded any GPG keys."
    end

    if missing_raw_key.any?
      ids = missing_raw_key.join(", ")
      headers["Note"] = "The keys with the following IDs couldn't be exported and need to be reuploaded #{ids}"
    end

    if decode_error.any?
      ids = decode_error.join(", ")
      headers["Error"] = "The keys with the following IDs couldn't be parsed #{ids}"
    end

    # combine keys and re-armor
    PgpArmor.encode(decoded.join,
      block_type: "PGP PUBLIC KEY BLOCK",
      headers: headers,
    )
  end

  # Convert the expires_at from gpgverify to the value we'll store in the db.
  #
  # data - Nil or a [epoch, offset] Array.
  #
  # Returns a Time instance or nil.
  def self.expires_at_value(data)
    return if data.nil?

    # Borrowed from GitRPC: https://github.com/github/github/blob/2ce2dabc6dd010b3dffdd29bca66d9e7f6b8fba4/vendor/gitrpc/lib/gitrpc/util.rb#L125-L149
    t, offset = data
    time = Time.at(t)
    if time.utc_offset != offset
      if offset == 0
        time.utc
      else
        time.localtime(offset)
      end
    end

    time
  end

  # A hex representation of a key id.
  #
  # key_id - The binary String key id to hex encode.
  #
  # Returns a hex String.
  def self.hex_key_id(key_id)
    key_id.unpack("H*").first.upcase
  end

  def raw_key_utf8_safe
    # Regex matches any 4-byte character (typically emojis, special symbols)
    if raw_key =~ /[\u{10000}-\u{10FFFF}]/
      errors.add(:raw_key, "contains unsupported characters")
    end
  end

  # Check if this public key is flagged to allow encryption
  #
  # Returns a boolean
  def can_encrypt?
    can_encrypt_comms? || can_encrypt_storage?
  end

  # Check if the public key is expired.
  #
  # Returns boolean.
  def expired?
    expiry = expires_at
    expiry && expiry < Time.now
  end

  # Verify the signature over the message using this key.
  #
  # message            - String message that was signed.
  # signature          - Binary String signature.
  #
  # Returns boolean.
  def verify(message, signature)
    GitHub.gpg.verify(message, signature, public_key)
  end

  # A hex representation of the key's id.
  #
  # Returns a hex String.
  def hex_key_id
    self.class.hex_key_id(key_id)
  end

  # Is this email address in the public key and is it a verified email address
  # on the user's account?
  #
  # Returns boolean.
  def allowed_email?(email, business: nil)
    return false unless email

    # For EMU convert the GPG key email address to match EMU primary email address
    # with a short code, since it is verified and not updatable for an emu user.
    email = email.downcase

    if business&.enterprise_managed_user_enabled?
      allowed_emails.include?(business.add_emu_shortcode_to_emails(email).downcase)
    else
      allowed_emails.include?(email)
    end
  end

  # Email addresses that are in the primary key and are verified on the user's
  # account.
  #
  # Returns an Array of downcased email address Strings.
  def allowed_emails
    @allowed_emails ||= begin
      if primary_key?
        emails = if GitHub.email_verification_enabled?
          verified_user_emails.pluck(:email).map(&:downcase)
        else
          user_emails.pluck(:email).map(&:downcase)
        end

        emails << legacy_stealth_email.downcase if legacy_stealth_email_exists?

        emails
      else
        primary_key&.allowed_emails || []
      end
    end
  end

  def legacy_stealth_email_exists?
    emails.where(email: legacy_stealth_email).exists?
  end

  # The legacy-format stealth email address for this key's user.
  #
  # Returns a String.
  def legacy_stealth_email
    loaded_user = User.find(user_id)
    StealthEmail.new(loaded_user).legacy_email
  end

  # Is this a primary key, as opposed to a sub key?
  #
  # Returns boolean.
  def primary_key?
    primary_key_id.nil?
  end

  # Is this a sub key, as opposed to a primary key?
  #
  # Returns boolean.
  def subkey?
    !primary_key?
  end

  # Public: GPG keys are accessible to everyone.
  def readable_by?(_)
    true
  end

  # Create GpgKeyEmails for this key.
  #
  # identities - An Array of Hashes, containing an "email" key.
  #
  # Returns nothing.
  def create_emails(identities)
    return if identities.nil?

    addresses = identities.map { |uid| uid["email"] }.reject(&:blank?)
    return if addresses.empty?

    # check if the user is enterprise managed and add the shortcode
    addresses_hash = if T.must(user).is_enterprise_managed?
      business = T.must(user).enterprise_managed_business
      addresses.to_h do |email|
        [business.add_emu_shortcode_to_emails(email), email]
      end
    else
      addresses.to_h { |email| [email, email] }
    end

    user_emails = Hash.new
    T.must(user).emails.where(email: addresses_hash.keys).each do |user_email|
      user_emails[user_email.email.downcase] = user_email.id
    end

    rows = addresses_hash.keys.map { |addr| [addresses_hash[addr], user_emails[addr.downcase], self.id] }

    GpgKeyEmail.connection.insert(Arel.sql(<<-SQL, rows: Arel::Nodes::ValuesList.new(rows)))
      INSERT INTO gpg_key_emails
      (email, user_email_id, gpg_key_id)
      :rows
    SQL
  end

  # Create subkeys for this primary key.
  #
  # subkeys - An Array of Hashes, containing "fingerprint" and "raw_data" keys.
  #
  # Returns nothing.
  def create_subkeys(subkeys, accept_revoked_keys: false)
    return if subkeys.nil? || subkeys.empty?

    now = Time.now

    # GPG Verify will return revoked subkeys with two bools in the hash, "revoked" and "compromised"
    # We will filter any subkeys that have been revoked or compromised.
    # If accept_revoked_keys is true, then we will filter any subkeys that have been revoked due to being compromised.
    filtered_subkeys = subkeys.reject { |s| s["revoked"] && (!accept_revoked_keys || s["compromised"]) }
    rows = filtered_subkeys.map do |subkey|
      expires_at = self.class.expires_at_value(subkey["expiration_at"])
      usage = subkey["usage"]

      [
        self.user_id,
        GitHub::SQL::ArelLiterals.binary(subkey["fingerprint"].byteslice(-8..-1)),
        GitHub::SQL::ArelLiterals.binary(subkey["raw_data"]),
        now,
        now,
        self.id,
        expires_at,
        usage["signing"],
        usage["encrypt_communications"],
        usage["encrypt_storage"],
        usage["certification"],
        subkey["revoked"] || false,
      ]
    end

    # subkeys exist but are all revoked/compromised. there is nothing to insert so return out before trying
    return if rows.empty?

    sql = Arel.sql(<<-SQL, rows: Arel::Nodes::ValuesList.new(rows))
      INSERT INTO gpg_keys
      (user_id, key_id, public_key, created_at, updated_at, primary_key_id, expires_at, can_sign, can_encrypt_comms, can_encrypt_storage, can_certify, revoked)
      :rows
    SQL
    self.class.connection.insert(sql)
  end

  include Instrumentation::Model

  # Prefix for audit log events.
  #
  # Returns a Symbol.
  def event_prefix
    :gpg_key
  end

  # Data about this key for instrumentation.
  #
  # Returns a Hash.
  def event_payload
    { user: user, key_id: hex_key_id }
  end

  # Instrument that this key was created in the audit log.
  #
  # payload - Hash of custom payload data.
  #
  # Returns nothing.
  def instrument_creation(payload = {})
    if primary_key?
      GitHub.dogstats.increment("gpg_key", tags: ["action:create"])
      instrument(:create, payload.merge(
        subkeys: subkeys.map(&:hex_key_id).sort,
        emails: emails.map(&:email),
        expires_at: expires_at,
        can_sign: can_sign,
        can_encrypt_comms: can_encrypt_comms,
        can_encrypt_storage: can_encrypt_storage,
        can_certify: can_certify,
        name: name,
        revoked: revoked?,
      ))
    end
  end

  # Instrument that this key was deleted in the audit log.
  #
  # payload - Hash of custom payload data.
  #
  # Returns nothing.
  def instrument_deletion(payload = {})
    if primary_key?
      GitHub.dogstats.increment("gpg_key", tags: ["action:destroy"])
      instrument(:destroy)
    end
  end

  def target_for_conditional_access
    user
  end
end
