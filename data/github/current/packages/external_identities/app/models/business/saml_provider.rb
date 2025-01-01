# typed: false
# frozen_string_literal: true

class Business::SamlProvider < ApplicationRecord::Domain::Users
  include GitHub::Validations
  include GitHub::Relay::GlobalIdentification
  include Business::SamlProvider::ProviderTypeDependency

  self.table_name = :business_saml_providers

  # Handles Signature & Digest Method mapping
  include SamlProviderAlgorithms

  # Recovery codes to skip SAML SSO
  include ExternalProviderRecoveryCodesMethods

  enum :scim_provisioning_state, { scim_provisioning_state_disabled: 0, scim_provisioning_state_enabled: 1 }

  belongs_to :target, foreign_key: "business_id", class_name: "Business", inverse_of: :saml_provider

  has_many :external_identities, as: :provider
  destroy_dependents_in_background :external_identities

  has_many :external_identity_sessions, through: :external_identities, source: :sessions

  has_many :external_groups, as: :provider
  destroy_dependents_in_background :external_groups

  before_validation :set_default_signature_method, :set_default_digest_method, :set_default_encryption_method,
    :set_default_key_transport_method

  validates_with SamlProviderSettingsValidator
  validate :user_provisioning_configuration
  validates :scim_provisioning_state, presence: true, inclusion: { in: scim_provisioning_states.keys }

  validates :sso_url, length: { maximum: 255 }, unicode3: true
  validates :issuer, length: { maximum: 255 }, unicode3: true
  validate :prevent_enabling_on_oidc_enabled_business

  encrypts :encrypted_key
  validates :encrypted_key, presence: true, if: proc { |p| p.encrypted_assertions == 1 }

  before_create :generate_secrets!
  after_create  :instrument_enable_saml
  after_destroy :instrument_disable_saml
  after_destroy :notify_team_sync_tenant
  after_update  :instrument_update_saml_provider_settings
  after_update  :notify_team_sync_tenant, if: :issuer_previously_changed?
  after_save    :instrument_recovery_codes_generated, if: :recovery_secret_previously_changed?

  attr_accessor :user_that_must_test_settings

  def business
    target
  end

  def business=(business)
    self.target = business
  end

  def successfully_tested_by?(user)
    Business::SamlProviderTestSettings.where(
      user: user,
      business: business,
      sso_url: sso_url,
      issuer: issuer,
      idp_certificate: idp_certificate,
    ).select(&:success?).any?
  end

  def identity_mapping
    @identity_mapping ||= Platform::Provisioning::IdentityMapping.new
  end

  def platform_type_name
    "EnterpriseIdentityProvider"
  end

  # Public: return the ExternalIdentities provisioned by the Enterprise's SAML Provider
  # for the given organization
  #
  # organization - organization to retrieve identities for
  #
  # Returns: an ActiveRelation of ExternalIdentities
  def external_identities_for_organization(organization)
    ActiveRecord::Base.connected_to(role: :reading) do
      get_external_identities_for_organization(organization)
    end
  end

  # Public: get a list of logins and external_id's for the organizations referenced by the
  # groups attributes in the given user_data
  #
  # user_data - UserData with the groups attributes we're looking at
  #
  # Returns: a Hash in the format of { login => external_id } for each group referenced in the
  #          user_data. external_id may be nil if the org does not yet have an external identity
  #          provisioned. Groups attributes in the given user_data that do not match to a login
  #          or external_id of an org belonging to this Enterprise are ignored.
  def group_ids(user_data:)
    group_ids = Platform::Provisioning::GroupsUserDataWrapper.new(user_data).groups
    return {} if group_ids.empty?

    ids_hash = business.
      organizations.
      includes(external_identities: :identity_attribute_records).
      where(login: group_ids).
      each_with_object({}) do |org, hash|
        hash[org.login] = org.external_identity&.scim_user_data&.external_id
      end

    return ids_hash if ids_hash.keys.length == group_ids.length

    guids = group_ids - ids_hash.keys
    user_data = Platform::Provisioning::SCIMGroupData.new
    user_data.append("externalId", guids)

    ExternalIdentity.
      by_provider(self).
      group_identities.
      by_scim_user_data(user_data).
      includes(:user, :identity_attribute_records).
      each_with_object(ids_hash) do |identity, hash|
        hash[identity.user.login] = identity.scim_user_data.external_id
      end

    ids_hash
  end

  # Public: is SAML provisioning enabled? SCIM provisioning is automatically enabled (for non EMU businesses) as soon
  # as SAML is enabled, but SAML provisioning is controlled by the `provisioning_enabled` flag
  # on Business::SamlProvider
  #
  # Returns: Boolean
  def saml_provisioning_enabled?
    return false unless GitHub.flipper[:enterprise_idp_provisioning].enabled?(business)

    provisioning_enabled?
  end

  # Public: When deprovisioning is enabled, any user with organization membership that's not
  # reflected in the identity provider's SAML metadata will be removed from those organizations.
  # this function checks that the IdP was correctly configured to send the groups element and that
  # there are groups attributes in ExternalIdentity.saml_user_data that match up with the current user
  # otherwise enabling deprovisioning would remove them (they would lock themselves out)
  #
  # user - User object
  #
  # Returns: Boolean
  def saml_groups_valid_for_deprovisioning?(user)
    return false unless provisioning_enabled?
    return true unless user

    external_identity = business.saml_provider.external_identities.linked_to(user).first
    return false if !external_identity

    saml_wrapper = Platform::Provisioning::GroupsUserDataWrapper.new(external_identity.saml_user_data)
    saml_wrapper.groups.any?
  end

  # Public: Checks if SCIM was enabled for the provider on GitHub Enterprise Server
  #
  # Returns Boolean
  def enterprise_server_scim_enabled?
    return false unless GitHub.enterprise?

    scim_provisioning_state_enabled?
  end

  # Public: Return a key to decrypt SAML encrypted assertions if one was
  #         created before (no key is created here!).
  #
  # Returns a OpenSSL private key
  def key
    return nil if !encrypted_assertions || !encrypted_key
    OpenSSL::PKey::RSA.new(encrypted_key)
  end

  private

  ##############################################################################################################
  # tl;dr: we want to make sure that enterprises enable user provisioning _before_ enabling deprovisioning.
  # We're doing this as a precautionary measure as enabling SAML deprovisioning without the proper SAML metadata
  # would cause users to be removed from all of an enterprise's organizations that they currently belong to.
  #
  # SCIM provisioning and deprovisioning is automatically enabled, since it's controlled by the IdP, and we need
  # to make sure to keep membership in sync as soon as the user enables Provisioning in the IdP.
  # ############################################################################################################
  def user_provisioning_configuration
    # TODO: replace with saml_provisioning_enabled? once :enterprise_idp_provisioning
    # feature flag is removed
    return if provisioning_enabled?

    if saml_deprovisioning_enabled?
      errors.add :saml_deprovisioning_enabled, \
        message: "Please enable SAML user provisioning before enabling SAML user deprovisioning"
    end
  end

  # Private: Validates sso_url to be present and a valid url
  def validate_sso_url
    uri = Platform::Scalars::URI.coerce_isolated_input(sso_url)
    unless uri.present? && uri.host.present? && %w(http https).include?(uri.scheme)
      errors.add(:sso_url, "is invalid")
    end
  end

  # Private: Valdiates no other provider exists for the business
  def prevent_enabling_on_oidc_enabled_business
    return unless business.oidc_enabled?

    errors.add :business_id,
      message: "cannot enable both SAML and OIDC single sign-on"
  end

  # Private: Validates idp_certificate to be present and valid X509 certificate
  def validate_idp_certificate
    cert = Platform::Scalars::X509Certificate.coerce_isolated_input(idp_certificate)
    unless cert.present?
      errors.add(:idp_certificate, "is invalid")
    end
  end

  def instrument_enable_saml
    business.instrument :enable_saml, audit_log_params
  end

  def instrument_disable_saml
    business.instrument :disable_saml, audit_log_params
  end

  def instrument_update_saml_provider_settings
    business.instrument :update_saml_provider_settings,
      audit_log_params.merge(audit_log_changes_for_update)
  end

  def audit_log_params
    if GitHub.flipper[:saml_encrypted_assertions].enabled?(business)
      {
        business_id:          business.id,
        business:             business,
        sso_url:              sso_url,
        issuer:               issuer,
        digest_method:        digest_method,
        signature_method:     signature_method,
        encrypted_assertions: encrypted_assertions,
        encryption_method:    encryption_method,
        key_transport_method: key_transport_method,
        business_created_at:  business.created_at,
        seats:                business.seats,
      }
    else
      {
        business_id:         business.id,
        business:            business,
        sso_url:             sso_url,
        issuer:              issuer,
        digest_method:       digest_method,
        signature_method:    signature_method,
        business_created_at: business.created_at,
        seats:               business.seats,
      }
    end
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
    business.team_sync_tenant&.saml_settings_changed(self)
  end

  # TODO remove this method and put code back into external_identities_for_organization when FF use_replica_for_group_syncer_graphql_calls is removed
  def get_external_identities_for_organization(organization)
    return ExternalIdentity.none unless business.organization_ids.include?(organization.id)

    # If Enterprise Provisioning is enabled, we'll store the group information with each
    # ExternalIdentity, so we can retrieve all the identities that the IdP has provisioned via
    # ExternalIdentity.by_group
    #
    # If Provisioning is not enabled for this enterprise, then we have no groups metadata saved,
    # so fall back to returning identities for all current and invited members. This way we are not
    # returning identities for users who have left the Organization, but have not been
    # de-provisioned by the IdP yet.
    if saml_provisioning_enabled?
      ExternalIdentity.by_provider(self).
        by_group([organization.login, organization.external_identity&.scim_user_data&.external_id]).
          distinct
    else
      user_ids = organization.member_ids

      invited_external_identity_ids = organization.pending_invitations.
        pluck(:external_identity_id).compact

      return ExternalIdentity.none if user_ids.empty? && invited_external_identity_ids.empty?

      ExternalIdentity.by_provider(self).
        where(user_id: user_ids).or(ExternalIdentity.where(id: invited_external_identity_ids))
    end
  end

  def instrument_recovery_codes_generated
    business.instrument :recovery_codes_generated
  end
end
