# typed: true
# frozen_string_literal: true

class IntegrationKey < ApplicationRecord::Domain::Integrations
  KEY_LENGTH = 2048

  MAX_KEYS = 25

  belongs_to :integration, touch: true
  belongs_to :creator, class_name: "User"

  validates :integration, presence: true
  validates :creator, presence: true
  validate :no_keys_for_attribution_only_system_identity

  before_validation :enforce_maximum_keys, on: :create
  before_validation :generate_rsa_key, on: :create

  before_destroy :prevent_last_key_deletion

  attr_accessor :private_key
  attr_accessor :skip_generate_key

  def public_key
    @public_key ||= OpenSSL::PKey::RSA.new(public_pem)
  end

  # Public: Compute the fingerprint of the integration's public key.
  #
  # Matches the output of `openssl sha256 -binary | openssl base64` given a DER-formatted public key.
  #
  # Taken from https://serverfault.com/a/697634/459549:
  #
  #   $ openssl rsa -in path_to_private_key -pubout -outform DER | openssl sha256 -binary | openssl base64
  #
  # Returns a fingerprint String.
  def fingerprint
    "SHA256:#{OpenSSL::Digest::SHA256.base64digest(public_key.to_der)}"
  end

  private

  def enforce_maximum_keys
    return unless new_record?
    return unless integration # This prevents an innacurate error message from being shown
    if T.must(integration).public_keys.count >= MAX_KEYS
      errors.add :base, "You cannot have more than #{MAX_KEYS} private keys."

      throw :abort
    end
  end

  def generate_rsa_key
    return if skip_generate_key && !self.public_pem.blank?
    self.private_key = OpenSSL::PKey::RSA.new(KEY_LENGTH)
    self.public_pem = private_key.public_key.to_pem
  end

  def prevent_last_key_deletion
    return if destroyed_by_association.present?
    if T.must(integration).public_keys.where("id <> ?", id).none?
      errors.add :base, "You cannot delete the only private key. Generate a new key first."

      throw :abort
    end
  end

  # Attribution-only system identities are not capable of generating keys
  # because they are not permitted to access api.github.com.
  def no_keys_for_attribution_only_system_identity
    if Apps::Privileged.capable?(:attribution_only_system_identity, app: integration)
      errors.add :base, "Attribution-only system identities are not permitted to create keys."
    end
  end
end
