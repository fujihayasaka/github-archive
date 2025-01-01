# typed: true
# frozen_string_literal: true
require "oidc/cache"

class Business::OIDCProvider < ApplicationRecord::Domain::Users
  MIGRATION_SUFFIX = " (SAML)"

  attr_accessor :migrate_to_oidc

  self.table_name = :business_oidc_providers

  # Recovery codes to skip OIDC SSO
  include ExternalProviderRecoveryCodesMethods

  enum :oidc_provider, {
    azure: 1,
  }

  belongs_to :target, foreign_key: "business_id", class_name: "Business", inverse_of: :oidc_provider

  has_many :external_identities, as: :provider

  has_many :external_identity_sessions, through: :external_identities, source: :sessions

  has_many :external_groups, as: :provider

  validates :oidc_provider, presence: true, inclusion: { in: oidc_providers.keys }
  # no test for it yet, since there is only one provider, add test when okta is added
  validates :oidc_provider, inclusion: { in: -> (i) { [i.oidc_provider_was] } }, on: :update
  validates :tenant_id, presence: true
  validates :tenant_id, inclusion: { in: -> (i) { [i.tenant_id_was] } }, on: :update
  validate :require_emu_business
  validate :prevent_enabling_on_saml_enabled_business

  before_create :generate_secrets!
  after_save  :instrument_recovery_codes_generated, if: :recovery_secret_previously_changed?
  after_commit :start_destroy_external_dependents_job, on: :destroy

  def business
    target
  end

  def business=(business)
    self.target = business
  end

  def platform_type_name
    "OIDCProvider"
  end

  def identity_mapping
    @identity_mapping ||= Platform::Provisioning::IdentityMapping.new
  end

  # To use this in test-setup, load the oidc/azure-configuration cassette
  def sso_url
    configuration = OIDC::Cache.get_configuration(oidc_provider)
    configuration.authorization_endpoint
  end

  # Public: Migration to OIDC SSO from SAML
  #
  # Returns nothing.
  def migrate_from_saml!
    return unless business.saml_provider

    business.saml_provider.external_identities.each do |external_identity|
      external_identity.provider = self

      scim_user_data = nil
      unless external_identity.disabled_at && external_identity.deleted_at
        scim_user_data = external_identity.scim_user_data

        scim_user_data.replace("displayName", scim_user_data.display_name + MIGRATION_SUFFIX) if scim_user_data.fetch("displayName").present?
        scim_user_data.replace("name.familyName", scim_user_data.family_name + MIGRATION_SUFFIX) if scim_user_data.fetch("name.familyName").present?
        scim_user_data.replace("name.formatted", scim_user_data.display_name + MIGRATION_SUFFIX) if scim_user_data.fetch("name.formatted").present?

        external_identity.scim_user_data = scim_user_data
      end

      if !external_identity.save
        Failbot.report!(
          external_identity,
          error_messages: external_identity.errors.first
        )
        return
      end

      if scim_user_data
        # Update the profile name for the user, to identify users that have not been migrated to a new OIDC provider
        # The profile name will be reset, once the user is provisioned through the new SCIM connector on OIDC application
        result = Platform::Provisioning::UserDataReconciler.reconcile(
          external_identity.user,
          scim_user_data,
          reason: :update,
          flags: { reconcile_methods: [:display_name] },
        )

        if result.has_fatal?
          Failbot.report!(
            result.errors.first,
            error_messages: result.error_message(:display_name)
          )
          return
        end
      end
    end

    business.saml_provider.external_groups.each do |external_group|
      external_group.provider = self

      external_group.display_name += MIGRATION_SUFFIX unless external_group.deleted_at

      if !external_group.save
        Failbot.report!(
          external_group,
          error_messages: external_group.errors.first
        )
        return
      end
    end

    business.saml_provider.reload.destroy
  end

  # Public: Returns a provider type that matches SAML defined provider type
  #
  # Returns a String
  def find_provider_type
    case oidc_provider
    when "azure"
      :azure_ad
    else
      :unknown
    end
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
    1.day.from_now
  end

  private

  def prevent_enabling_on_saml_enabled_business
    return if migrate_to_oidc.present?
    return unless business.saml_provider.present?

    errors.add :business_id,
      message: "cannot enable both SAML and OIDC single sign-on"
  end

  def require_emu_business
    return if business.enterprise_managed?

    errors.add :business_id,
      message: "must be an enterprise-managed enterprise account"
  end

  def instrument_recovery_codes_generated
    business.instrument :recovery_codes_generated
  end

  def start_destroy_external_dependents_job
    business&.set_removing_external_provider(self.class.name)
    DestroyExternalProviderDependentsJob.perform_later(
      provider_id: id,
      provider_type: self.class.name,
      business_id: business_id,
      caller: self.class.name
    )
  end
end
