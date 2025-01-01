# typed: true
# frozen_string_literal: true

class Organization::SamlProvider < ApplicationRecord::Domain::Users
  include GitHub::Relay::GlobalIdentification

  self.table_name = :organization_saml_providers

  SESSION_LENGTH_IN_MINUTES_MIN = 30
  SESSION_LENGTH_IN_MINUTES_MAX = 10080 # 1 week

  # handles Signature & Digest Method mapping
  include SamlProviderAlgorithms

  # Recovery codes to skip SAML SSO
  include ExternalProviderRecoveryCodesMethods

  belongs_to :target, foreign_key: "organization_id", class_name: "Organization", inverse_of: :saml_provider

  def organization
    target
  end

  def organization=(org)
    self.target = org
  end

  has_many :external_identities, as: :provider
  destroy_dependents_in_background :external_identities

  has_many :external_identity_sessions, through: :external_identities, source: :sessions

  has_many :external_groups, as: :provider
  destroy_dependents_in_background :external_groups

  before_validation :set_default_signature_method, :set_default_digest_method, :set_default_encryption_method,
  :set_default_key_transport_method

  validates_with SamlProviderSettingsValidator

  validates :session_length_in_minutes, numericality: { only_integer: true, greater_than_or_equal_to: SESSION_LENGTH_IN_MINUTES_MIN, less_than_or_equal_to: SESSION_LENGTH_IN_MINUTES_MAX }, allow_nil: true

  before_create :generate_secrets!
  after_create  :instrument_enable_saml
  after_destroy :instrument_disable_saml
  after_destroy :notify_team_sync_tenant
  after_update  :instrument_update_saml_provider_settings
  after_update  :notify_team_sync_tenant, if: :issuer_previously_changed?
  after_save    :instrument_recovery_codes_generated, if: :recovery_secret_previously_changed?

  attr_accessor :reason
  attr_accessor :user_that_must_test_settings

  def destroy(reason = nil)
    @reason = reason
    super()
  end

  def enforce!
    update(enforced: true)
  end

  def identity_mapping
    @identity_mapping ||= Platform::Provisioning::IdentityMapping.new
  end

  def platform_type_name
    "OrganizationIdentityProvider"
  end

  def successfully_tested_by?(user)
    Organization::SamlProviderTestSettings.where(
      user: user,
      organization: organization,
      sso_url: sso_url,
      issuer: issuer,
      idp_certificate: idp_certificate,
    ).select(&:success?).any?
  end

  def saml_provisioning_enabled?
    true
  end

  # Public: is SCIM provisioning enabled? - temporarily hard coded to return false until this is implemented at the org level.
  #
  # Returns: Boolean
  def scim_provisioning_enabled?
    false
  end

  # Public: Checks if SCIM was enabled for the provider on GitHub Enterprise Server
  #
  # Returns Boolean
  def enterprise_server_scim_enabled?
    false
  end

  # Public: Gets the default session expiration for this provider class
  #
  # Returns ActiveSupport::TimeWithZone
  def default_session_expiration
    if organization&.feature_flag_enabled_or_raise?(:org_saml_session_length_configurable) && session_length_in_minutes.present? # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
      T.must(session_length_in_minutes).minutes.from_now
    else
      1.day.from_now
    end
  end

  private

  # Private: Validates sso_url to be present and a valid url
  def validate_sso_url
    uri = Platform::Scalars::URI.coerce_isolated_input(sso_url)
    unless uri.present? && uri.host.present? && %w(http https).include?(uri.scheme)
      errors.add(:sso_url, "is invalid")
    end
  end

  # Private: Validates idp_certificate to be present and valid X509 certificate
  def validate_idp_certificate
    cert = Platform::Scalars::X509Certificate.coerce_isolated_input(idp_certificate)
    unless cert.present?
      errors.add(:idp_certificate, "is invalid")
    end
  end

  def instrument_enable_saml
    organization.instrument :enable_saml, audit_log_params
  end

  def instrument_disable_saml
    organization.instrument :disable_saml, audit_log_params.merge(reason: @reason)
  end

  def instrument_update_saml_provider_settings
    organization.instrument :update_saml_provider_settings,
      audit_log_params.merge(audit_log_changes_for_update)
  end

  def audit_log_params
    {
      org_id: organization.id,
      org: organization,
      sso_url: sso_url,
      issuer: issuer,
      digest_method: digest_method,
      signature_method: signature_method,
      enforced: enforced?,
      org_created_at: organization.created_at,
      seats: organization.seats,
      filled_seats: organization.filled_seats,
      pending_invites: organization.pending_invitations.count,
    }
  end

  def audit_log_changes_for_update
    changes_to_log = saved_changes.except(:idp_certificate, :updated_at)

    # include `idp_certificate` if it was changed, but filter out the values
    if saved_change_to_idp_certificate?
      changes_to_log[:idp_certificate] = ["[FILTERED]", "[FILTERED]"]
    end

    {
      # fields that were changed, including `idp_certificate` and `updated_at`
      changed: saved_changes.keys,

      # changed values, before and after
      changes: changes_to_log,
    }
  end

  def notify_team_sync_tenant
    return unless organization.has_team_sync_tenant?
    organization.team_sync_tenant.saml_settings_changed(self)
  end

  def instrument_recovery_codes_generated
    organization.instrument :recovery_codes_generated
  end
end
