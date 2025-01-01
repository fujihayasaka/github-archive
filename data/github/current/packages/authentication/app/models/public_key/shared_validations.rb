# typed: true
# frozen_string_literal: true

# These validations and methods are common to both PublicKey and GitSigningSshPublicKey
module PublicKey::SharedValidations
  extend ActiveSupport::Concern
  extend T::Helpers

  PUBLIC_KEY_RECOMMENDATION = "GitHub recommends using ssh-keygen to generate a RSA key of at least 2048 bits.".freeze

  KEY_TYPE_RSA = "ssh-rsa".freeze
  KEY_TYPE_DSS = "ssh-dss".freeze

  requires_ancestor { ActiveRecord::Base }

  included do
    T.bind(self, T.class_of(ActiveRecord::Base))

    validate :key_type_validity
    validate :key_validity
    validate :uncompromised_key
    validate :key_length, on: :create
    validate :not_weak_key, on: :create
    validate :uniqueness_of_key
    validate :user_has_email, on: :create

    include GitHub::Validations
    validates :title, length: { maximum: 255 }, allow_blank: true
  end #included

  # Public: returns the fingerprint in the format of ssh-keygen
  #
  # Returns the fingerprint in a format suitable to return to users in the UI or API.
  def fingerprint
    T.bind(self, T.any(PublicKey, GitSigningSshPublicKey))

    if GitHub.multi_tenant_enterprise? && fingerprint_sha256
      "SHA256:#{fingerprint_sha256.split("_")[0]}"
    else
      "SHA256:#{fingerprint_sha256}"
    end
  end

  def weak_key?
    return false unless parsed_key.algo == SSHData::PublicKey::ALGO_RSA
    GitHub::SSH.weak_rsa_key?(parsed_key.openssl)
  rescue SSHData::Error
    true
  end

  def allowed_algos
    T.bind(self, T.any(PublicKey, GitSigningSshPublicKey))

    self.class.allowed_algos
  end

  protected

  def strip_whitespace
    T.bind(self, T.any(PublicKey, GitSigningSshPublicKey))

    self[:key] = self.class.strip_whitespace(self[:key])
  end

  def set_title
    T.bind(self, T.any(PublicKey, GitSigningSshPublicKey))

    if self[:title].blank? && self[:key] !~ /[\n\r]/ && !self[:key].split(" ")[2].blank?
      self[:title] = self[:key].split(" ")[2]
    end
  end

  def strip_prefix
    T.bind(self, T.any(PublicKey, GitSigningSshPublicKey))

    self[:key] = self.class.strip_prefix(self[:key])
  end

  def strip_comments
    T.bind(self, T.any(PublicKey, GitSigningSshPublicKey))

    self[:key] = self.class.strip_comments(self[:key]) if self[:key] !~ /[\n\r]/
  end

  def set_fingerprint_sha256
    T.bind(self, T.any(PublicKey, GitSigningSshPublicKey))

    self.fingerprint_sha256 = begin
      if GitHub.multi_tenant_enterprise? && (current_tenant = GitHub::CurrentTenant.get)
        parsed_key.fingerprint << "_#{current_tenant.shortcode}"
      else
        parsed_key.fingerprint
      end
    rescue SSHData::Error
      "bogus"
    end
  end

  def key_bit_length
    case parsed_key.algo
    when SSHData::PublicKey::ALGO_RSA
      parsed_key.openssl.params["n"].num_bits
    when SSHData::PublicKey::ALGO_DSA
      parsed_key.openssl.params["p"].num_bits
    when SSHData::PublicKey::ALGO_ECDSA256, SSHData::PublicKey::ALGO_SKECDSA256
      256
    when SSHData::PublicKey::ALGO_ECDSA384
      384
    when SSHData::PublicKey::ALGO_ECDSA521
      521
    when SSHData::PublicKey::ALGO_ED25519, SSHData::PublicKey::ALGO_SKED25519
      256
    else 0
    end
  rescue SSHData::Error
    0
  end

  def parsed_key
    T.bind(self, T.any(PublicKey, GitSigningSshPublicKey))

    @parsed_key ||= SSHData::PublicKey.parse(key)
  end

  def key_type_validity
    T.bind(self, T.any(PublicKey, GitSigningSshPublicKey))

    return if !errors[:key].empty?

    unless allowed_algos.include?(parsed_key.algo)
      errors.add :key, "is invalid. It must begin with #{allowed_algos.map { |k| "'#{k}'" }.join(", ")}. Check that you're copying the public half of the key"
    end

  rescue SSHData::Error
    errors.add(:key, "is invalid. You must supply a key in OpenSSH public key format")
  end

  # Internal: validate that this key is structurally correct by using
  # `ssh-keygen` to decode the key and generate the key's fingerprint. If the
  # key is corrupt `ssh-keygen` will fail to generate a valid fingerprint.
  def key_validity
    T.bind(self, T.any(PublicKey, GitSigningSshPublicKey))

    return if !errors[:key].empty?
    set_fingerprint_sha256 if fingerprint_sha256.nil?

    fingerprint_split = fingerprint_sha256.split "_"

    if fingerprint_sha256 == "bogus" || fingerprint_split[0] !~ /\A[A-Za-z0-9\+\/=]+\z/
      GitHub.dogstats.increment("ssh_key.fingerprint", tags: ["error:invalid_fingerprint"])
      errors.add :key, "is invalid. Ensure you've copied the file correctly"
    end

    if GitHub.multi_tenant_enterprise? && !fingerprint_split[1]
      GitHub.dogstats.increment("ssh_key.fingerprint", tags: ["error:missing_shortcode"])
      errors.add :key, "could not be saved due to an internal error. Please try again"
    end
  end

  def uniqueness_of_key
    T.bind(self, T.any(PublicKey, GitSigningSshPublicKey))

    return if !errors[:key].empty?

    cond = if new_record?
      ["fingerprint_sha256 = ?", fingerprint_sha256]
    else
      ["fingerprint_sha256 = ? and id <> ?", fingerprint_sha256, id]
    end

    if self.class.select("id, `key`").where(cond).first
      errors.add :key, "is already in use"
    end
  end

  # The MIN_KEY_BIT_LENGTH constant comes from either the GitSigningSshPublicKey or PublicKey class
  # A GitSigningSshPublicKey key is a minimum of 2047 bits, while a PublicKey key is a minimum of 1023 bits
  # We'd like to eventually make this for 2047 for both https://github.com/github/pse-architecture/issues/652
  def key_length
    T.bind(self, T.any(PublicKey, GitSigningSshPublicKey))

    return if !errors[:key].empty?

    # this validation is only relevant for RSA and DSA
    if key_type == KEY_TYPE_RSA || key_type == KEY_TYPE_DSS
      # Some versions of PuTTY for Windows had a bug where they would generate keys
      # of length (2^n)-1. So we don't end up blocking these keys (since they're
      # essentially just as strong as a key of size (2^n)), we compare the key
      # bit length to MIN_KEY_BIT_LENGTH - 1.
      if key_bit_length < self.class.min_key_bit_length
        errors.add :key, "is too short. #{PUBLIC_KEY_RECOMMENDATION}"
      end
    end
  end

  # Verify that the key is not weak, where the definition of weak is dependent
  # on the type of key.
  def not_weak_key
    return if !errors[:key].empty?

    if weak_key?
      errors.add :key, "is weak. #{PUBLIC_KEY_RECOMMENDATION}"
    end
  end

  # Internal: validate that this key is not compromised
  def uncompromised_key
    T.bind(self, T.any(PublicKey, GitSigningSshPublicKey))

    return if !errors[:key].empty?

    if key.present? && GitHub::SSH.blocklisted_key?(parsed_key)
      errors.add :key, "is blocked because its private key has been compromised."
    end
  end

  module ClassMethods
    # Public: Normalizes the provided key String, removing whitespace.
    def strip_whitespace(key)
      key.to_s.strip.gsub(/[\r\n]/, "")
    end

    # Public: Strips comments from the provided key String.
    def strip_comments(key)
      key.split(" ")[0, 2].join(" ")
    end

    # Public: Strip prefixes "SSH:" and "SSHKey:".
    def strip_prefix(key)
      key.sub(/\ASSH(Key)?:/, "")
    end

    # Public: Normalize key to the key data, removing whitespace, stripping
    # prefixes and comments.
    def normalize_key(key)
      strip_comments(strip_prefix(strip_whitespace(key)))
    end

    def allowed_algos
      algos = [SSHData::PublicKey::ALGO_RSA, SSHData::PublicKey::ALGO_ECDSA256, SSHData::PublicKey::ALGO_ECDSA384,
        SSHData::PublicKey::ALGO_ECDSA521]

      unless GitHub.fips_mode?
        algos << SSHData::PublicKey::ALGO_ED25519
      end

      algos << SSHData::PublicKey::ALGO_SKECDSA256
      algos << SSHData::PublicKey::ALGO_SKED25519 unless GitHub.fips_mode?

      algos
    end
  end
end # module PublicKey::SharedValidations
