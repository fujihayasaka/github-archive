# typed: false
# frozen_string_literal: true

# Used to store SAML IdP settings temporarily while a business admin is
# testing their SAML configuration.
#
# Mirrors the attributes and validations of the Business::SamlProvider model.
# Note: Does not have associated ExternalIdentity records.
class Business::SamlProviderTestSettings < ApplicationRecord::Domain::Users
  include GitHub::Validations
  SUCCESS = "success"
  FAILURE = "failure"

  # Used for reporting invalid SAML Response needles
  class InvalidSamlResponseError < RuntimeError; end

  self.table_name = :business_saml_provider_test_settings

  # Handles Signature & Digest Method mapping
  include SamlProviderAlgorithms

  belongs_to :user
  belongs_to :business

  before_validation :set_default_signature_method, :set_default_digest_method, :set_default_encryption_method,
  :set_default_key_transport_method

  validates_with SamlProviderSettingsValidator

  encrypts :encrypted_key
  validates :encrypted_key, presence: true, if: proc { |p| p.encrypted_assertions == 1 }

  validates :sso_url, length: { maximum: 255 }, unicode3: true
  validates :issuer, length: { maximum: 255 }, unicode3: true

  validate :validate_issuer_for_emus

  scope :all_for_user_and_business, -> (user, business) {
    where(user_id: user.try(:id), business_id: business.try(:id)).
      order("created_at DESC")
  }

  attr_reader :message

  # Public: Retrieve test settings (optionally updating status and message) for
  #         the most recent test performed by a given user on a business.
  #
  # result - Hash with "status" and "message" (optional, if set, updates
  #          attributes on returned object).
  #
  # Returns an instance of Business::SamlProviderTestSettings (a new one if user
  # never tested this business).
  def self.most_recent_for(user:, business:, result: nil, cleanup_old_settings: false)
    settings = all_for_user_and_business(user, business).first || new
    result ||= {}
    settings.set_status(status: result["status"], message: result["message"])
  end

  # Saves a new test settings record for a given user and business.
  #
  # Note: Removes existing settings for the user and business to prevent
  # table bloat.
  def self.save_for(user:, business:, settings: {})
    all_for_user_and_business(user, business).destroy_all

    test_settings = new(
      settings.merge(user_id: user.id, business_id: business.id),
    )

    test_settings.save(validate: false)
    test_settings
  end

  # Internal: Remember the status of these settings. Status itself is a database
  # column (so we can confirm a test was successful upon saving); message is
  # just an attribute (it's not needed after display).
  #
  # Returns itself
  def set_status(status: nil, message: "")
    self.status = status
    @message = message
    self
  end

  # Public: Do these settings represent a successful SSO test?
  #
  # Returns a Boolean
  def success?
    /\A#{SUCCESS}\z/.match(status)
  end

  # Public: Do these settings represent a failure of the SSO flow test?
  #
  # Returns a Boolean
  def failure?
    !success?
  end

  def validate_issuer_for_emus
    return unless business&.enterprise_managed_user_enabled?

    return if business.saml_sso_enabled? #If this business alreaedy has SSO enabled, we don't want to stop them from being able to update their certificate

    if issuer.blank?
      errors.add(:issuer, "is required for Enterprise Managed User enabled enterprises")
    end
  end

  def aad_or_okta?
    Business::SamlProvider::ProviderTypeDependency.find_provider_type_from_issuer(issuer) == :azure_ad || Business::SamlProvider::ProviderTypeDependency.find_provider_type_from_issuer(issuer) == :okta
  end

  # Public: Return a key to decrypt SAML encrypted assertions if one was
  #         created before (no key is created here!).
  #
  # Returns a OpenSSL private key
  def key
    return nil if !encrypted_assertions || !encrypted_key
    OpenSSL::PKey::RSA.new(encrypted_key)
  end
end
