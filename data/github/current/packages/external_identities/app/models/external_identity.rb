# typed: false
# frozen_string_literal: true

class ExternalIdentity < ApplicationRecord::Domain::Users
  include GitHub::Relay::GlobalIdentification
  include Instrumentation::Model
  include GitHub::BatchedScope

  NAME_IDS = [Platform::Provisioning::SamlUserData::NAME_ID] + Platform::Provisioning::SamlUserData::DEFAULT_USER_NAME_ATTRIBUTE
  NAME_ID = Platform::Provisioning::SamlUserData::NAME_ID
  USER_NAME = "userName"
  VALID_PROVIDER_TYPES = %w(Organization::SamlProvider Business::SamlProvider Business::OIDCProvider)

  EXTERNAL_IDENTIFIER_ATTRIBUTE_NAMES = {
      azuread: "http://schemas.microsoft.com/identity/claims/objectidentifier",
  }.freeze

  attr_readonly :guid
  attr_writer :prefilled_group_members

  belongs_to :user
  has_one :organization_invitation, dependent: :nullify, inverse_of: :external_identity
  has_one :external_identity_refresh_token, dependent: :destroy
  belongs_to :provider, polymorphic: true
  delegate :target, to: :provider

  has_many :sessions,
    class_name: "ExternalIdentitySession",
    dependent: :delete_all

  has_many :user_sessions,
    through: :sessions,
    source: :user_session

  # Internal: Records backing an ExternalIdentities attributes provided
  # by the identity provider. Use the `saml_user_data` to interact
  # with these attributes instead of directly accessing the records.
  has_many :identity_attribute_records,
    class_name: "ExternalIdentityAttribute",
    dependent: :delete_all,
    autosave: true,
    extend: ExternalIdentityAttribute::AssociationExtension

  # Internal: Records backing a display_name attributes will generate correct
  # display_name for the external identity.
  has_many :display_name_records, -> { where(scheme: "scim", name: ["displayName", "name.formatted", "name.givenName", "name.familyName", "userName"]) }, class_name: "ExternalIdentityAttribute"

  has_many :external_identity_group_memberships, dependent: :destroy

  validate :validate_saml_name_id_is_unique
  validate :validate_scim_user_name_is_unique
  validate :validate_external_id_is_unique
  validates :provider, presence: true
  validates :provider_type, inclusion: VALID_PROVIDER_TYPES

  before_create :set_guid
  before_destroy :cancel_pending_invite, if: -> { user && !user&.is_enterprise_managed? }
  before_destroy :cleanup_destroyed_user, if: -> { cleanup_destroyed_user_data? }
  before_save :truncate_user_name
  before_save :truncate_name_id
  before_save :truncate_external_id
  before_save :truncate_saml_external_id

  after_commit :update_team_memberships, on: :update
  after_update :set_provisioned_status_changed
  after_commit :update_business_license_usage, only: [:disable, :enable]

  alias_attribute :guest_collaborator, :restricted_user

  # Public: Finds all identities that are not marked as deleted.
  #
  # Returns a scope.
  scope :not_deleted, -> {
    where(deleted_at: nil)
  }

  # Public: Finds all identities that are not marked as disabled.
  #
  # Returns a scope.
  scope :not_disabled, -> {
    where(disabled_at: nil)
  }

  # Public: Fids all identities that are not disabled and not deleted.
  #
  # Returns a scope
  scope :not_disabled_and_deleted, -> {
    where(disabled_at: nil, deleted_at: nil)
  }

  # Public: Finds all identities linked to a given User.
  #
  # user    - The User the identities should be linked to.
  #
  # Returns a scope.
  scope :linked_to, -> (user) { where(user_id: user.id) }

  # Public: Finds all identities which are not linked to a User account.
  #
  # Returns a scope.
  scope :unlinked, -> { where(user_id: nil) }

  # Public: Finds all identities linked to a given resource type (User or Organization)
  #  Note: will not return any unlinked identities
  #
  # Returns a scope.
  scope :by_resource_type, -> (resource_type) {
    joins(:user).where(users: { type: resource_type })
  }
  scope :user_identities, -> { by_resource_type("User") }
  scope :group_identities, -> { by_resource_type("Organization") }

  # Public: Returns all the identities, except for the ones linked to Organizations. Gets all the
  # unlinked identities and identities linked to Users.
  #
  # Returns a scope.
  scope :unlinked_or_users, -> {
    identities_scope = joins("LEFT OUTER JOIN users on external_identities.user_id = users.id")
    identities_scope.unlinked.or(identities_scope.where(users: { type: "User" }))
  }

  # Public: Finds ExternalIdentities which are for the given provider.
  #
  # provider  - An instance of the provider (e.g. Organization::SamlProvider)
  #
  # Returns a scope.
  scope :by_provider, -> (provider) {
    where(provider_id: provider.id, provider_type: provider.class.name)
  }

  # Public: Finds ExternalIdentities which are for the given user_name
  #
  # user_name - a string that is assigned when SAML or SCIM provisioned
  #
  # Returns a scope.
  # This is an extremely expensive query. Please use a read replica if possible.
  scope :by_scim_username, -> (username) {
    return none unless username

    where(user_name: username)
  }

  # Public: Find ExternalIdentities that matches the given identifier
  #
  # identifier - UserData identifier attribute value
  #
  # Returns a scope.
  # This is an extremely expensive query. Please use a read replica if possible.
  scope :by_identifier_attribute, -> (identifier) {
    return none unless identifier

    where("user_name = :user_name OR name_id = :user_name", { user_name: identifier })
  }

  # Public: Find ExternalIdentities that matches the given identifier
  #
  # external_id - UserData external ID value
  #
  # Returns a scope.
  scope :by_external_id_attribute, -> (external_id) {
    return none unless external_id

    where(external_id: external_id).or(ExternalIdentity.where(saml_external_id: external_id))
  }

  # Public: Find SCIM provisioned ExternalIdentities that match any of the
  # provided emails.
  #
  # # emails - An Array of email addresses.
  #
  # Returns a scope.
  # This is an extremely expensive query. Please use a read replica if possible.
  scope :by_scim_emails, -> (emails) {
    return none unless emails.any?

    scope = ExternalIdentityAttribute.select(:external_identity_id)
      .where(scheme: :scim, name: :emails, value: Array.wrap(emails))
      .group(:external_identity_id).having("COUNT(*) = 1")

    joins(sanitize_sql([<<~SQL, scope]))
      INNER JOIN (?) AS user_data ON user_data.external_identity_id = external_identities.id
    SQL
  }

  # Public: Find ExternalIdentities that match any of the provided emails in
  # any of the default attribute mapping fields for emails or user_name.
  #
  # emails - An Array of email addresses.
  #
  # Returns a scope.
  scope :by_emails_in_attributes, -> (emails) {
    return none unless emails.any?
    attribs = (Platform::Provisioning::SamlUserData::DEFAULT_ATTRIBUTE_MAPPINGS[:user_name] | Platform::Provisioning::SamlUserData::DEFAULT_ATTRIBUTE_MAPPINGS[:emails])
    where(<<-SQL, value: Array.wrap(emails), name: attribs)
      EXISTS (
        SELECT 1 FROM external_identity_attributes AS attrs
        WHERE attrs.external_identity_id = external_identities.id
          AND attrs.name IN (:name)
          AND attrs.value IN (:value)
        LIMIT 1
      )
    SQL
  }

  scope :by_emails_in_attributes_candidate, -> (emails) {
    return none unless emails.any?

    attribs = (Platform::Provisioning::SamlUserData::DEFAULT_ATTRIBUTE_MAPPINGS[:user_name] | Platform::Provisioning::SamlUserData::DEFAULT_ATTRIBUTE_MAPPINGS[:emails])
    scope = ExternalIdentityAttribute.select(:external_identity_id)
      .where(name: attribs, value: Array.wrap(emails))
      .group(:external_identity_id).having("COUNT(*) = 1")

    joins(sanitize_sql([<<~SQL, scope]))
      INNER JOIN (?) AS user_data ON user_data.external_identity_id = external_identities.id
    SQL
  }

  # Internal: Finds ExternalIdentities which have been provisioned by the
  # specified scheme.
  #
  # scheme    - The scheme name by which the attributes were provided (e.g. :saml).
  #
  # Returns a scope.
  # This is an extremely expensive query. Please use a read replica if possible.
  scope :provisioned_by_with_attributes, -> (scheme) {
    where(<<-SQL, scheme: scheme)
      EXISTS (
        SELECT 1 FROM external_identity_attributes AS attrs
        WHERE attrs.external_identity_id = external_identities.id
          AND attrs.scheme = :scheme
        LIMIT 1
      )
    SQL
  }

  # Internal: Finds ExternalIdentities which have been provisioned by the
  # specified scheme.
  #
  # scheme    - The scheme name by which the attributes were provided (e.g. :saml).
  #
  # Returns a scope.
  # This query uses user_name (populated by scim) to filter scim provisioned records
  # and nama_id (populated by saml) to filter saml provisioned records
  scope :provisioned_by, -> (scheme) {
    if scheme == :scim
      where.not(user_name: nil)
    else
      where.not(name_id: nil)
    end
  }

  # Internal: Finds ExternalIdentities with matching UserData for a given scheme.
  # For an external identity to be returned all specified user_data attribute values
  # must match.
  #
  # Please use scheme specific helpers like `by_saml_user_data` where possible.
  #
  # scheme    - The scheme name by which the attributes were provided (e.g. :saml).
  # user_data - A UserData object containing the required attributes.
  #
  # Returns a scope.
  scope :by_user_data, -> (scheme:, user_data:) {
    return none if user_data&.none?

    scope = user_data.reduce(ExternalIdentityAttribute.select(:external_identity_id).none) do |conditions, attr|
      conditions.or(ExternalIdentityAttribute.where({
        scheme: scheme, name: attr["name"], value: attr["value"]
      }))
    end

    scope = scope.group(:external_identity_id).having("COUNT(*) = ?", user_data.count)

    joins(sanitize_sql([<<~SQL, scope]))
      INNER JOIN (?) AS user_data ON user_data.external_identity_id = external_identities.id
    SQL
  }

  # Public: Finds ExternalIdentities with matching SAML UserData.
  #
  # user_data - A UserData object containing the required attributes.
  #
  # Returns a scope.
  scope :by_saml_user_data, -> (user_data) {
    by_user_data(scheme: :saml, user_data: user_data)
  }

  # Public: Finds ExternalIdentities with matching SCIM UserData.
  #
  # user_data - A UserData object containing the required attributes.
  #
  # Returns a scope.
  scope :by_scim_user_data, -> (user_data) {
    by_user_data(scheme: :scim, user_data: user_data)
  }

  # Public: Finds ExternalIdentities that belong to the specified group
  #
  #   group_ids - group identifiers, can be names, guids, or combination of both
  #
  # Returns a scope
  scope :by_group, -> (group_ids) {
    where(<<-SQL, group_ids: group_ids, group_attr_names: Platform::Provisioning::SamlUserData::GROUP_ATTRIBUTE_NAMES)
      EXISTS (
        SELECT 1 FROM external_identity_attributes AS attrs
        WHERE attrs.external_identity_id = external_identities.id
          AND attrs.name IN (:group_attr_names)
          AND attrs.value IN (:group_ids)
        LIMIT 1
      )
    SQL
  }

  scope :scim_filter, -> (filter) {
    SCIM::Filter.apply(filter, ExternalIdentity, scope: all)
  }

  scope :with_attributes, -> { includes(:identity_attribute_records) }

  # Public: Finds ExternalIdentities with SAML UserData NameID matching the
  # given identity.
  #
  # identity - A ExternalIdentity object containing SAML user data.
  #
  # Returns a scope.
  scope :identities_with_same_name_id_as, -> (identity) {
    # SAML user_data NameID is exposed as user_name
    with_same_name_id = by_provider(identity.provider)
      .where(name_id: identity.name_id)

    with_same_name_id = with_same_name_id.where.not(id: identity.id) if identity.persisted?
    with_same_name_id
  }

  # Public: Finds ExternalIdentities with SCIM UserData userName matching the
  # given identity.
  #
  # identity - A ExternalIdentity object containing SCIM user data.
  #
  # Returns a scope.
  scope :identities_with_same_user_name_as, -> (identity) {
    with_same_user_name = by_provider(identity.provider)
      .where(user_name: identity.user_name)

    with_same_user_name = with_same_user_name.where.not(id: identity.id) if identity.persisted?
    with_same_user_name
  }

  # Public: Finds ExternalIdentities with external id matching the
  # given identity.
  #
  # identity - A ExternalIdentity object containing user data.
  #
  # Returns a scope.
  scope :identities_with_same_external_id_as, -> (identity) {
    external_id_values = [identity.external_id, identity.saml_external_id].compact.uniq
    with_same_external_id = by_provider(identity.provider).where("external_id IN (?) OR saml_external_id IN (?)", external_id_values, external_id_values)

    with_same_external_id = with_same_external_id.where.not(id: identity.id) if identity.persisted?
    with_same_external_id
  }

  # Public: Preloads associations required for API serialization using the
  # scim_identities_hash and its variants.
  scope :with_scim_preloads, -> {
    includes(
      :identity_attribute_records,
      :user,
      { organization_invitation: :teams }
    ).preload({ provider: :target })
  }

  scope :with_scim_managed_preloads, -> {
    includes(
      :identity_attribute_records,
      :user,
    ).preload({ provider: :target })
  }

  scope :with_team_memberships, -> {
    joins(external_identity_group_memberships: [external_group: [:external_group_teams]])
  }

  # Internal: Removes emails, avatars, ssh keys and gpg keys of the user account
  #
  # Returns nothing.
  def self.cleanup_user(user, deploy_keys: false)
    user.email_roles.delete_all
    user.emails.delete_all

    user.avatars.destroy_all

    user.public_keys.destroy_all
    user.oauth_accesses.destroy_all
    user.gpg_keys.destroy_all

    # cleanup deploy_keys for user-owned repos
    if deploy_keys
      repo_ids = user.repositories.pluck(:id)
      deploy_keys = PublicKey.where(repository_id: repo_ids)
      User.transaction do
        deploy_keys.each do |key|
          key.destroy_with_explanation(:user_deprovisioned)
        end
      end
      GitHub.dogstats.histogram("scim_deprovisioning.remove_deploy_keys", deploy_keys.size)
    end

    user.saml_mapping&.destroy

    options = { rebuild_contributions: true }

    UserContributionCacheRefreshJob.perform_later(user.id, options)
  end

  # Public: Find ExternalIdentities that matches the given identifier
  #
  # user_data - A UserData object containing the identifier attributes.
  # mapping   - a Platform::Provisioning::IdentityMapping object
  # identifier_attributes - (Optional) Specific mapping attributes to be used instead
  #     of the default specified by the IdentityMapping object.
  # match_saml_identities - for mapping purposes just want to query saml records
  #
  # Returns ActiveRecord::Relation or none.
  def self.get_by_identifier(user_data, mapping:, identifier_attributes: mapping.identifier_attributes, match_saml_identities: false)
    identifier = mapping.value_from_user_data(user_data).presence
    return none unless identifier

    # Since the identifier_attributes include both userName and NameID as attributes
    # both values will need to be checked.  Once the user_name is fully populated we can
    # remove fall back to attributes.  We will check which attribute was passed in and only
    # check appropriate one.
    if identifier_attributes.include?(NAME_ID)
      result = where(name_id: identifier)
      return result unless result.to_a.empty?

      result = if match_saml_identities
        provisioned_by(:saml).where(user_name: identifier)
      else
        where(user_name: identifier)
      end
    elsif identifier_attributes.include?(USER_NAME)
      result = where(user_name: identifier)
    end

    result
  end

  # Public: Find ExternalIdentities that matches the given external id only matches on SCIM populated external_id.
  #         Used in scim_mapper since we want to match on the external_id that is only populated by SCIM.
  #
  # user_data - A UserData object containing the external id attribute.
  # mapping   - a Platform::Provisioning::IdentityMapping object
  # external_id_attributes - (Optional) Specific mapping attributes to be used instead
  #     of the default specified by the IdentityMapping object.
  #
  # Returns ActiveRecord::Relation or none.
  def self.get_by_external_id_scim(user_data, mapping:, external_id_attributes: mapping.external_id_attributes)
    external_id = user_data.external_id
    return none unless external_id

    result = where(external_id: external_id)
    return result unless result.to_a.empty?

    none
  end

  # Public: Find ExternalIdentities that matches the given external id
  #
  # user_data - A UserData object containing the external id attribute.
  # mapping   - a Platform::Provisioning::IdentityMapping object
  # external_id_attributes - (Optional) Specific mapping attributes to be used instead
  #     of the default specified by the IdentityMapping object.
  #
  # Returns ActiveRecord::Relation or none.
  def self.get_by_external_id(user_data, mapping:, external_id_attributes: mapping.external_id_attributes)
    external_id = user_data.external_id
    return none unless external_id

    result = where(external_id: external_id)
    return result unless result.to_a.empty?

    # In very rare cases, the external_id may be stored in the saml_external_id column
    # when it was populated by SAML and it might be different from the external_id column.
    # Since it is a rare case it is faster to run a separate query to check the saml_external_id column.
    result = where(saml_external_id: external_id)
    return result unless result.to_a.empty?

    none
  end

  # Public: removes an external identity for an organization or business member
  #
  # provider    - The identity provider the external identity is for.
  # user        - The User the external identity is for.
  # instrumentation_payload  - audit log payload
  def self.unlink(provider:, user:, instrumentation_payload: {})
    unlink_users(
      where(
        provider_id: provider.id,
        provider_type: provider.class.name,
        user_id: user.id
      )
    )

    # Will record an audit log event if not empty
    if !instrumentation_payload.empty?
      provider.target.instrument_external_identity_revoked(instrumentation_payload)
    end
  end

  # Public: removes SAML-provisioned external identities, provisioned by the given provider,
  # for the specified list of users. Does not remove ExternalIdentity's that have any SCIM
  # provisioned attributes.
  #
  # provider    - The identity provider which provisioned the external identities
  # user_ids    - id's of Users whose identities are to be removed
  #
  # Returns: nothing
  def self.unlink_saml_identities(provider:, user_ids:)
    base_scope = ExternalIdentity.
      provisioned_by(:saml).
      includes(:identity_attribute_records).
      where(
        provider_id: provider.id,
        provider_type: provider.class.name,
        user_id: user_ids)

    saml_identity_ids = []
    # ExternalIdentity.provisioned_by(:saml) will return all ExternalIdentity's that have SAML
    # attributes, but it can't return identities that ONLY have SAML-provisioned attributes, so
    # adding this extra loop here to reject any that also have SCIM-provisioned attributes.
    base_scope.in_batches do |external_identities|
      saml_identity_ids += \
        external_identities.to_a.reject do |identity|
          identity.identity_attribute_records.attributes_by_scheme[:scim].any?
        end.map(&:id)
    end

    unlink_users(ExternalIdentity.where(id: saml_identity_ids)) unless saml_identity_ids.empty?
  end

  # Public: unlinks (destroys) the specified external identities. Works in batches of
  # 1000 at a time so the query doesn't time out.
  #
  # external_identities - identities to destroy
  #
  # Returns: nothing
  def self.unlink_users(external_identities)
    external_identities.in_batches do |external_identities|     # load and destroy 1,000 at a time
      with_write { external_identities.destroy_all }
    end
  end

  # Public: Determines if a user has already linked their account to a given
  # provider.
  #
  # provider    - The identity provider the external identity is for.
  # user        - The User the external identity is for.
  #
  # Returns a boolean.
  def self.linked?(provider:, user:)
    attributes = {
      provider_id: provider.id,
      provider_type: provider.class.name,
      user_id: user.id,
    }
    where(attributes).exists?
  end

  # Public: has the given identity's NameID been taken by an existing external
  # identity?
  #
  # Returns a Boolean.
  def self.name_id_already_taken?(identity)
    identities_with_same_name_id_as(identity).not_deleted.any?
  end

  def self.identity_provider(team)
    provider = team.organization.team_sync_tenant.provider_type.to_sym
    EXTERNAL_IDENTIFIER_ATTRIBUTE_NAMES.fetch(provider) { "externalId" }
  end

  def prefilled_group_members
    return nil unless user&.organization?

    # this is used in group SCIM on enterprise for a single
    @prefilled_group_members ||= provider.
      external_identities_for_organization(user).
      provisioned_by_with_attributes(:scim).
      includes(:identity_attribute_records)
  end

  # Public: Returns user data we have on hand provided by SAML.
  #
  # Returns a Platform::Provisioning::SamlUserData instance.
  def saml_user_data
    saml_attrs = identity_attribute_records.attributes_by_scheme["saml"]
    user_data = Platform::Provisioning::SamlUserData.new(saml_attrs)
    Platform::Provisioning::AttributeMappedUserData.new(user_data)
  end

  # Public: Sets SAML identity attributes defined by the given UserData object.
  #
  # user_data   - A Platform::Provisioning::UserData instance.
  #
  # Returns nothing.
  def saml_user_data=(user_data)
    identity_attribute_records.set_scheme_attributes("saml", user_data.to_a)
  end

  # Public: Returns group data we have on hand provided by SAML.
  #
  # Returns a Platform::Provisioning::SamlGroupData instance.
  def saml_group_data
    saml_attrs = identity_attribute_records.attributes_by_scheme["saml"]
    Platform::Provisioning::SamlGroupData.new(saml_attrs)
  end

  # Public: Returns the SCIM user data we have.
  #
  # Returns a Platform::Provisioning::ScimUserData instance.
  def scim_user_data
    scim_attrs = identity_attribute_records.attributes_by_scheme["scim"]
    user_data = Platform::Provisioning::ScimUserData.new(scim_attrs)
    Platform::Provisioning::AttributeMappedUserData.new(user_data)
  end

  # Public: Returns the SCIM display name for a user stored in the attributes
  #
  # Returns String
  def display_name
    return "" if display_name_records.empty?
    user_data = Platform::Provisioning::ScimUserData.new(display_name_records)
    Platform::Provisioning::AttributeMappedUserData.new(user_data).display_name
  end

  # Public: Sets SCIM identity attributes defined by the given UserData object.
  #
  # user_data   - A Platform::Provisioning::UserData instance.
  #
  # Returns nothing.
  def scim_user_data=(user_data)
    identity_attribute_records.set_scheme_attributes("scim", user_data.to_a)
  end

  # Public: Returns the SCIM group data we have.
  #
  # Returns a Platform::Provisioning::SCIMGroupData instance.
  def scim_group_data
    scim_attrs = identity_attribute_records.attributes_by_scheme["scim"]
    Platform::Provisioning::SCIMGroupData.new(scim_attrs)
  end

  # Internal: Prefix for auditing / instrumentation
  def event_prefix
    :external_identity
  end

  def event_context(prefix: event_prefix)
    context = {
      "#{event_prefix}_guid".to_sym => guid,
      "#{event_prefix}_nameid".to_sym => saml_user_data.name_id,
      "#{event_prefix}_username".to_sym => scim_user_data.user_name,
    }

    if scim_user_data.roles.present? && !scim_user_data.roles.empty?
      context["#{event_prefix}_scim_roles".to_sym] = scim_user_data.roles.map { |role| Platform::Provisioning::RoleReconciler.human_readable_role(role) }.join(", ")
    end

    context
  end

  # Disable an external identity by adding disable_at time
  #
  # Returns false if update fails to set the disable_at time, true otherwise
  def disable
    update(disabled_at: Time.now)
  end

  # Enable an external identity by removing disable_at time
  #
  # Returns false if update fails to set the disable_at time, true otherwise
  def enable
    update(disabled_at: nil)
  end

  # Mark an external identity as deleted by adding deleted_at time
  #
  # Returns false if update fails to set the deleted_at time, true otherwise
  def mark_deleted
    if update(deleted_at: Time.now)
      # since we are marking identity as deleted we also need to reset external_id to nil
      update(external_id: nil)
      update(saml_external_id: nil)
      identity_attribute_records.delete_all
    end
  end

  # Public: Creates an external identity provision audit log event
  #
  # action - the provision action: provision (default) or unsuspend
  #
  # Returns nothing
  def instrument_provision(action: :provision)
    instrument_event(:provision, action)
  end

  # Public: Creates an external identity update audit log event
  #
  # Returns nothing
  def instrument_update
    instrument_event(:update, :update)
  end

  # Public: Creates an external identity deprovision audit log event
  #
  # action - the deprovision action: delete (default) or suspend
  #
  # Returns nothing
  def instrument_deprovision(action: :delete)
    instrument_event(:deprovision, action)
  end

  def set_refresh_token(refresh_token)
    if external_identity_refresh_token.present?
      external_identity_refresh_token.update(encrypted_refresh_token: refresh_token)
    else
      ExternalIdentityRefreshToken.create(external_identity: self, encrypted_refresh_token: refresh_token)
    end
  end

  # Public: Returns a list of emails pulled from the external identity attributes
  # that we expect to contain emails
  #
  # It's best to also include the `with_attributes` scope when calling this method on a collection so that
  # the attribute data can be eager loaded
  #
  # Returns: Array of Strings
  def emails
    # A user could have both saml_user_data and scim_user_data so we try saml_user_data first
    # as SCIM '.emails' already pulls in user_name if emails is empty and the username looks
    # like an email but SAML doesn't. We'll try that later if we need to.
    ext_emails = saml_user_data.emails
    if ext_emails.empty?
      ext_emails = scim_user_data.emails
    end
    # If we still don't have any emails, try the SAML username
    if ext_emails.empty? && saml_user_data.user_name&.match(User::EMAIL_REGEX)
      ext_emails = [saml_user_data.user_name]
    end
    # Add the NameID if it looks like an email as we may have matched on it from the
    # by_emails_in_attributes scope and it may not be in the list of email addresses
    # in the saml data.
    if saml_user_data.name_id&.match(User::EMAIL_REGEX)
      ext_emails << saml_user_data.name_id
    end
    # Add the SCIM userName if it looks like an email
    if scim_user_data.user_name&.match(User::EMAIL_REGEX)
      ext_emails << scim_user_data.user_name
    end

    ext_emails.uniq
  end

  private

  attr_accessor :has_provisioned_status_changed

  # Private: Creates an external identity audit log event and Hydro event
  #
  # operation - an operation that was performed
  #
  # Returns nothing
  def instrument_event(operation, action)
    instrument operation,
      operation: operation,
      action: action,
      id: id,
      user: user.display_login,
      user_id: user_id,
      provider_type: provider_type,
      external_identity_external_id: saml_external_id || external_id,
      scim_user_id: guid

    GlobalInstrumenter.instrument("external_identity.#{operation}", {
      action: action,
      identity: self,
    })
  end

  def validate_saml_name_id_is_unique
    return unless provider
    return unless name_id
    # no need to run the query if the name_id has not changed
    return unless name_id_changed?

    identities = self.class.identities_with_same_name_id_as(self).not_deleted

    if identities.any?
      message = duplicate_saml_identity_error_message(identities.first.user)
      errors.add(:base, message)
    end
  end

  # Private: Creates an error message for duplicate SAML identity
  #
  # Returns a String
  def duplicate_saml_identity_error_message(taken_by)
    message = "Your GitHub user account @#{user&.login} is currently "
    message += if name_id_was
      "linked to the '#{name_id_was}' SAML identity. "
    else
      "unlinked. "
    end
    message += "However, you are attempting to authenticate with your Identity Provider using the '#{name_id}' SAML identity "
    if taken_by
      message += "which is already linked to a different GitHub user account in the organization. Please reach out to one of your GitHub organization owners for assistance."
    else
      message += "which is currently unlinked in the organization. Please reach out to one of your GitHub organization owners for assistance."
    end

    message
  end

  def validate_scim_user_name_is_unique
    return unless provider
    return unless user_name
    # no need to run the query if the user_name has not changed
    return unless user_name_changed?

    # ignore validation of user_name if scim_user_data is setting the active flag to false
    return if scim_managed_enterprise? && !scim_user_data.active?

    identities = if scim_managed_enterprise?
      # have to check both disabled and deleted (disabled is not set when deleted is),
      # mark deleted removes attributes and since
      # we are checking for userName in the attributes, we need to check both disabled and deleted
      self.class.identities_with_same_user_name_as(self).not_disabled_and_deleted
    else
      self.class.identities_with_same_user_name_as(self).not_deleted
    end

    if identities.any?
      taken_by = identities.first.user
      message = "External login '#{user_name}' is already linked to @#{ taken_by }'s account."
      errors.add(:base, message)
    end
  end

  def validate_external_id_is_unique
    return unless provider
    return unless external_id
    # no need to run the query if the external_id has not changed
    return unless external_id_changed?

    identities = self.class.identities_with_same_external_id_as(self)

    if identities.any?
      taken_by = identities.first.user
      message = "External ID '#{external_id}' is already linked to @#{ taken_by }'s account."
      errors.add(:base, message)
    end
  end

  def set_guid
    self.guid = SimpleUUID::UUID.new.to_guid
  end

  # Private: Clean up any user data and suspend a user when external identity is distroyed.
  #  This method is only called for EMU and GHES
  #
  # Returns Nothing
  def cleanup_destroyed_user
    # suspend the user before deleting the external identities
    user.suspend(
      "User has been suspended by deleting their external identity",
      actor: user,
      hard_flag: true,
      instrument_abuse_classification: false,
    ) if user

    # only cleanup EMU and GHES provisioned users
    self.class.cleanup_user(user)
  end

  def cancel_pending_invite
    return unless organization_invitation.try(:pending?)
    organization_invitation.cancel(actor: organization_invitation.organization)
  end

  def truncate_user_name
    if user_name.present? && user_name.length > 255
      self.user_name = "#{user_name[0...255]}"
    end
  end

  def truncate_name_id
    if name_id.present? && name_id.length > 255
      self.name_id = "#{name_id[0...255]}"
    end
  end

  def truncate_external_id
    if external_id.present? && external_id.length > 128
      self.external_id = "#{external_id[0...128]}"
    end
  end

  def truncate_saml_external_id
    if saml_external_id.present? && saml_external_id.length > 128
      self.saml_external_id = "#{saml_external_id[0...128]}"
    end
  end

  # Private: This method is responsible for keeping team memberships in sync with the external
  #   identity.
  # Suspension will not remove the external identity group membership records, but it will remove
  #   a team/organization membership if the group was linked.
  # Unsuspend will add team/organization membership based on the linkage of the external group
  # Hard Delete (deleted_at is set) will remove all of the external identity group memberships.
  #
  # Returns Nothing
  def update_team_memberships

    if !user
      # external identity is not linked to groups
      return unless external_identity_group_memberships.any?
    end

    if self.has_provisioned_status_changed
      begin
        ExternalGroupMemberReconcileJob.perform_later(external_identity_id: self.id, caller: self.class.name)
      ensure
        self.has_provisioned_status_changed = false
      end
    end
  end

  # Private: Check if the identity is SCIM managed.  Returns true for GHES with SCIM
  # enabled on an enterprise, and enterprise managed users.
  #
  # Returns Boolean
  def scim_managed_enterprise?
    user&.is_enterprise_managed? ||
    provider_type != "Organization::SamlProvider" && provider.business&.enterprise_managed_user_enabled? ||
    GitHub.enterprise? && provider_type != "Organization::SamlProvider" && provider.scim_provisioning_state_enabled?
  end

  # Private: Check if the user data needs to be cleaned up. Returns true for enterprise managed users that are not the
  # first emu owner.
  #
  # Returns Boolean
  def cleanup_destroyed_user_data?
    user&.is_emu_and_not_first_owner?
  end

  # Private: Update the enterprise license cache when the external identity changes licensed state.
  #
  # Returns nothing
  def update_business_license_usage
    return if GitHub.enterprise?
    return unless provider
    return unless scim_managed_enterprise?

    GitHub.logger.info(
      "info.message" => "Queueing business license usage update",
      "gh.external_identity.id" => self.id,
      "gh.user.id" => user&.id,
      "gh.user.login" => user&.login,
      "gh.business.id" => provider&.business&.id,
      "gh.business.name" => provider&.business&.name,
    )

    provider.business&.update_license_usage
  end

  # Private: Sets has_provisioned_status_changed based on whether deleted_at or disabled_at has changed.
  #
  # Returns nothing
  def set_provisioned_status_changed
    self.has_provisioned_status_changed ||= saved_change_to_attribute?(:deleted_at) || saved_change_to_attribute?(:disabled_at)
  end
end
