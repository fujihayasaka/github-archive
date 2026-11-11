# typed: true
# frozen_string_literal: true

# Used to store SAML IdP settings temporarily while an organization admin is
# testing their SAML configuration.
#
# Mirrors the attributes and validations of the Organization::SamlProvider model.
# Note: Does not have associated Organization::SamlExternalIdentity records.
class Organization::SamlProviderTestSettings < ApplicationRecord::Domain::Users
  SUCCESS = "success"
  FAILURE = "failure"

  # used for reporting invalid SAML Response needles
  class InvalidSamlResponseError < RuntimeError; end

  self.table_name = "organization_saml_provider_test_settings"

  # handles Signature & Digest Method mapping
  include SamlProviderAlgorithms

  belongs_to :user
  belongs_to :organization

  before_validation :set_default_signature_method, :set_default_digest_method, :set_default_encryption_method,
  :set_default_key_transport_method

  validates_with SamlProviderSettingsValidator

  scope :all_for_user_and_org, -> (user, org) {
    where(user_id: user.try(:id), organization_id: org.try(:id)).
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
  def self.most_recent_for(user:, org:, result: nil, cleanup_old_settings: false)
    settings = all_for_user_and_org(user, org).first || new
    result ||= {}
    settings.set_status(status: result["status"], message: result["message"])
  end

  # Saves a new test settings record for a given user and organization.
  #
  # Note: Removes existing settings for the user and organization to prevent
  # table bloat.
  def self.save_for(user:, organization:, settings: {})
    all_for_user_and_org(user, organization).destroy_all

    test_settings = new(
      settings.merge(user_id: user.id, organization_id: organization.id),
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
end
